"""PDF utilities for converting PDFs to images"""
import fitz
import io
from PIL import Image


def pdf_to_images_high_quality(pdf_path, dpi=144, image_format="PNG"):
    """
    Convert PDF to images using a generator (streaming, memory-efficient)

    Args:
        pdf_path: Path to PDF file
        dpi: Resolution for conversion (default 144)
        image_format: Output image format (default PNG)

    Yields:
        PIL Image objects one at a time (memory-efficient streaming)
    """
    pdf_document = fitz.open(pdf_path)

    zoom = dpi / 72.0
    matrix = fitz.Matrix(zoom, zoom)

    for page_num in range(pdf_document.page_count):
        page = pdf_document[page_num]

        pixmap = page.get_pixmap(matrix=matrix, alpha=False)
        Image.MAX_IMAGE_PIXELS = None

        if image_format.upper() == "PNG":
            img_data = pixmap.tobytes("png")
            img = Image.open(io.BytesIO(img_data))
        else:
            img_data = pixmap.tobytes("png")
            img = Image.open(io.BytesIO(img_data))
            if img.mode in ('RGBA', 'LA'):
                background = Image.new('RGB', img.size, (255, 255, 255))
                background.paste(img, mask=img.split()[-1] if img.mode == 'RGBA' else None)
                img = background

        # Yield image immediately instead of storing in list
        yield img

        # Explicit cleanup
        del pixmap
        if hasattr(img_data, 'close'):
            img_data.close()

    pdf_document.close()
