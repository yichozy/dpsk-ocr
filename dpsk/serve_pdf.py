import os
import io
import uuid
import shutil
import torch
from pathlib import Path
from typing import Optional
from concurrent.futures import ThreadPoolExecutor
from dotenv import load_dotenv

from fastapi import FastAPI, File, UploadFile, HTTPException, BackgroundTasks, Security, Depends
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from fastapi.responses import FileResponse, JSONResponse
from pydantic import BaseModel

# Load environment variables from .env file
load_dotenv()

from pdf_utils import pdf_to_images_high_quality
from processing_utils import (
    pil_to_pdf_img2pdf,
    re_match,
    process_image_with_refs
)

# Environment setup
if torch.version.cuda == '11.8':
    os.environ["TRITON_PTXAS_PATH"] = "/usr/local/cuda-11.8/bin/ptxas"
os.environ['VLLM_USE_V1'] = '0'
os.environ["CUDA_VISIBLE_DEVICES"] = '0'

from config import MODEL_PATH, PROMPT, SKIP_REPEAT, MAX_CONCURRENCY, NUM_WORKERS, CROP_MODE

from deepseek_ocr import DeepseekOCRForCausalLM
from vllm.model_executor.models.registry import ModelRegistry
from vllm import LLM, SamplingParams
from process.ngram_norepeat import NoRepeatNGramLogitsProcessor
from process.image_process import DeepseekOCRProcessor

# Register custom model
ModelRegistry.register_model("DeepseekOCRForCausalLM", DeepseekOCRForCausalLM)

# Initialize FastAPI app
app = FastAPI(
    title="DeepSeek OCR PDF Service",
    description="OCR service for PDF documents with layout detection",
    version="1.0.0"
)

# Security setup
security = HTTPBearer()
AUTH_TOKEN = os.getenv("AUTH_TOKEN")

def verify_token(credentials: HTTPAuthorizationCredentials = Security(security)):
    """Verify the authentication token"""
    if AUTH_TOKEN is None:
        # If no AUTH_TOKEN is set, allow access without authentication
        return True

    if credentials.credentials != AUTH_TOKEN:
        raise HTTPException(
            status_code=401,
            detail="Invalid authentication token",
            headers={"WWW-Authenticate": "Bearer"},
        )
    return True

# Initialize model (loaded once at startup)
llm = LLM(
    model=MODEL_PATH,
    hf_overrides={"architectures": ["DeepseekOCRForCausalLM"]},
    block_size=256,
    enforce_eager=False,
    trust_remote_code=True,
    max_model_len=8192,
    swap_space=0,
    max_num_seqs=MAX_CONCURRENCY,
    tensor_parallel_size=1,
    gpu_memory_utilization=0.9,
    disable_mm_preprocessor_cache=True
)

# Setup logits processors and sampling params
logits_processors = [
    NoRepeatNGramLogitsProcessor(
        ngram_size=20,
        window_size=50,
        whitelist_token_ids={128821, 128822}  # <td>, </td>
    )
]

sampling_params = SamplingParams(
    temperature=0.0,
    max_tokens=8192,
    logits_processors=logits_processors,
    skip_special_tokens=False,
    include_stop_str_in_output=True,
)

# Create directories for temporary files
TEMP_DIR = Path("tmp/pdf_ocr")
TEMP_DIR.mkdir(exist_ok=True)


class ProcessingStatus(BaseModel):
    """Response model for processing status"""
    job_id: str
    status: str
    message: Optional[str] = None


class OCRResult(BaseModel):
    """Response model for OCR results"""
    job_id: str
    markdown_content: str
    markdown_with_det: str
    layout_pdf_url: str
    extracted_images: list[str]


def process_single_image(image, prompt):
    """Prepare single image for batch processing"""
    cache_item = {
        "prompt": prompt,
        "multi_modal_data": {
            "image": DeepseekOCRProcessor().tokenize_with_images(
                images=[image],
                bos=True,
                eos=True,
                cropping=CROP_MODE
            )
        },
    }
    return cache_item


def cleanup_job_files(job_id: str):
    """Clean up temporary files for a job"""
    job_dir = TEMP_DIR / job_id
    if job_dir.exists():
        shutil.rmtree(job_dir)


def process_pdf_internal(pdf_path: str, job_id: str, output_dir: Path):
    """
    Internal function to process PDF

    Args:
        pdf_path: Path to input PDF file
        job_id: Unique job identifier
        output_dir: Directory to save outputs
    """
    try:
        # Create output directories
        images_dir = output_dir / "images"
        images_dir.mkdir(exist_ok=True)

        # Convert PDF to images
        images = pdf_to_images_high_quality(pdf_path)

        # Preprocess images in parallel
        prompt = PROMPT
        with ThreadPoolExecutor(max_workers=NUM_WORKERS) as executor:
            batch_inputs = list(executor.map(
                lambda img: process_single_image(img, prompt),
                images
            ))

        # Run OCR inference
        outputs_list = llm.generate(batch_inputs, sampling_params=sampling_params)

        # Process outputs
        contents_det = ''
        contents = ''
        draw_images = []

        for jdx, (output, img) in enumerate(zip(outputs_list, images)):
            content = output.outputs[0].text

            # Check for proper completion
            if '<｜end▁of▁sentence｜>' in content:
                content = content.replace('<｜end▁of▁sentence｜>', '')
            else:
                if SKIP_REPEAT:
                    continue

            page_num = f'\n<--- Page Split --->'
            contents_det += content + f'\n{page_num}\n'

            # Extract layout references
            matches_ref, matches_images, mathes_other = re_match(content)

            # Draw bounding boxes and extract images
            image_draw = img.copy()
            result_image = process_image_with_refs(
                image_draw,
                matches_ref,
                jdx,
                str(output_dir)
            )
            draw_images.append(result_image)

            # Replace image references with markdown links
            for idx, a_match_image in enumerate(matches_images):
                content = content.replace(
                    a_match_image,
                    f'![](images/{jdx}_{idx}.jpg)\n'
                )

            # Clean up other references
            for idx, a_match_other in enumerate(mathes_other):
                content = content.replace(a_match_other, '') \
                    .replace('\\coloneqq', ':=') \
                    .replace('\\eqqcolon', '=:') \
                    .replace('\n\n\n\n', '\n\n') \
                    .replace('\n\n\n', '\n\n')

            contents += content + f'\n{page_num}\n'

        # Save outputs
        mmd_det_path = output_dir / "output_det.mmd"
        mmd_path = output_dir / "output.mmd"
        pdf_out_path = output_dir / "output_layouts.pdf"

        with open(mmd_det_path, 'w', encoding='utf-8') as f:
            f.write(contents_det)

        with open(mmd_path, 'w', encoding='utf-8') as f:
            f.write(contents)

        pil_to_pdf_img2pdf(draw_images, str(pdf_out_path))

        return {
            "success": True,
            "markdown_path": str(mmd_path),
            "markdown_det_path": str(mmd_det_path),
            "layout_pdf_path": str(pdf_out_path),
            "images_dir": str(images_dir)
        }

    except Exception as e:
        return {
            "success": False,
            "error": str(e)
        }


@app.get("/")
async def root():
    """Root endpoint - API information"""
    return {
        "service": "DeepSeek OCR PDF Service",
        "version": "1.0.0",
        "status": "running"
    }


@app.get("/health")
async def health_check():
    """Health check endpoint"""
    return {"status": "healthy", "model_loaded": True}


@app.post("/process_pdf", response_model=ProcessingStatus)
async def process_pdf(
    file: UploadFile = File(...),
    background_tasks: BackgroundTasks = None,
    authenticated: bool = Depends(verify_token)
):
    """
    Upload and process a PDF file

    Args:
        file: PDF file to process

    Returns:
        Job ID and status
    """
    # Validate file type
    if not file.filename.endswith('.pdf'):
        raise HTTPException(status_code=400, detail="Only PDF files are supported")

    # Generate unique job ID
    job_id = str(uuid.uuid4())

    # Create job directory
    job_dir = TEMP_DIR / job_id
    job_dir.mkdir(exist_ok=True)

    # Save uploaded file
    pdf_path = job_dir / "input.pdf"
    try:
        contents = await file.read()
        with open(pdf_path, 'wb') as f:
            f.write(contents)
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to save file: {str(e)}")

    # Process PDF
    result = process_pdf_internal(str(pdf_path), job_id, job_dir)

    if not result["success"]:
        raise HTTPException(status_code=500, detail=f"Processing failed: {result['error']}")

    return ProcessingStatus(
        job_id=job_id,
        status="completed",
        message="PDF processed successfully"
    )


@app.get("/result/{job_id}/markdown")
async def get_markdown(job_id: str, authenticated: bool = Depends(verify_token)):
    """Get markdown output for a job"""
    mmd_path = TEMP_DIR / job_id / "output.mmd"

    if not mmd_path.exists():
        raise HTTPException(status_code=404, detail="Result not found")

    with open(mmd_path, 'r', encoding='utf-8') as f:
        content = f.read()

    return {"job_id": job_id, "content": content}


@app.get("/result/{job_id}/markdown_det")
async def get_markdown_with_detection(job_id: str, authenticated: bool = Depends(verify_token)):
    """Get markdown with detection annotations for a job"""
    mmd_det_path = TEMP_DIR / job_id / "output_det.mmd"

    if not mmd_det_path.exists():
        raise HTTPException(status_code=404, detail="Result not found")

    with open(mmd_det_path, 'r', encoding='utf-8') as f:
        content = f.read()

    return {"job_id": job_id, "content": content}


@app.get("/result/{job_id}/layout_pdf")
async def get_layout_pdf(job_id: str, authenticated: bool = Depends(verify_token)):
    """Download layout visualization PDF"""
    pdf_path = TEMP_DIR / job_id / "output_layouts.pdf"

    if not pdf_path.exists():
        raise HTTPException(status_code=404, detail="PDF not found")

    return FileResponse(
        pdf_path,
        media_type="application/pdf",
        filename=f"layout_{job_id}.pdf"
    )


@app.get("/result/{job_id}/images")
async def list_extracted_images(job_id: str, authenticated: bool = Depends(verify_token)):
    """List all extracted images for a job"""
    images_dir = TEMP_DIR / job_id / "images"

    if not images_dir.exists():
        raise HTTPException(status_code=404, detail="Images not found")

    images = list(images_dir.glob("*.jpg"))
    return {
        "job_id": job_id,
        "images": [img.name for img in images],
        "count": len(images)
    }


@app.get("/result/{job_id}/images/{image_name}")
async def get_extracted_image(job_id: str, image_name: str, authenticated: bool = Depends(verify_token)):
    """Download a specific extracted image"""
    image_path = TEMP_DIR / job_id / "images" / image_name

    if not image_path.exists():
        raise HTTPException(status_code=404, detail="Image not found")

    return FileResponse(
        image_path,
        media_type="image/jpeg",
        filename=image_name
    )


@app.delete("/result/{job_id}")
async def delete_job(job_id: str, authenticated: bool = Depends(verify_token)):
    """Delete all files associated with a job"""
    cleanup_job_files(job_id)
    return {"job_id": job_id, "status": "deleted"}


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
