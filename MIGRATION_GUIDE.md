# Migration Guide - Synchronous to Asynchronous API

## Overview

This guide helps you migrate from the old synchronous API to the new asynchronous API with task tracking.

## What Changed?

### Before (Synchronous)
```python
# Upload PDF and wait for results (blocks for minutes)
response = requests.post("/process_pdf", files={"file": pdf})
result = response.json()

# Results are immediately available
job_id = result["job_id"]
status = result["status"]  # Always "completed"
```

### After (Asynchronous)
```python
# Upload PDF and get task ID immediately (returns in milliseconds)
response = requests.post("/process_pdf", files={"file": pdf})
result = response.json()

job_id = result["job_id"]
status = result["status"]  # "pending" initially

# Poll for completion
while True:
    status_resp = requests.get(f"/result/{job_id}/status")
    if status_resp.json()["status"] == "completed":
        break
    time.sleep(5)

# Now retrieve results
```

## Breaking Changes

### 1. `/process_pdf` Response Format

**Before:**
```json
{
  "job_id": "abc-123",
  "status": "completed",
  "message": "PDF processed successfully"
}
```

**After:**
```json
{
  "job_id": "abc-123",
  "status": "pending",
  "message": "PDF processing initiated. Use /result/{job_id}/status to check progress."
}
```

**Impact**: You can no longer assume results are ready immediately after upload.

**Migration**: Add status polling logic (see examples below).

### 2. Result Endpoints Return HTTP 202 When Not Ready

**Before:**
- Results always available immediately
- Either 200 OK or 404 Not Found

**After:**
- May return **HTTP 202 Accepted** if still processing
- Requires retry logic

**Example:**
```python
# OLD CODE (won't work correctly anymore)
response = requests.get(f"/result/{job_id}/markdown")
markdown = response.json()["content"]  # May fail with KeyError

# NEW CODE (handles 202 properly)
response = requests.get(f"/result/{job_id}/markdown")
if response.status_code == 202:
    print("Still processing, wait and retry")
elif response.status_code == 200:
    markdown = response.json()["content"]
```

### 3. Result Responses Include Status Field

**Before:**
```json
{
  "job_id": "abc-123",
  "content": "markdown here..."
}
```

**After:**
```json
{
  "job_id": "abc-123",
  "status": "completed",
  "content": "markdown here..."
}
```

**Impact**: Minimal - extra field added, existing code should work.

## Migration Strategies

### Strategy 1: Simple Polling (Quick Fix)

Add a helper function to wait for completion:

```python
import time
import requests

def wait_for_completion(job_id, timeout=600, poll_interval=5):
    """Wait for job to complete or fail"""
    start_time = time.time()

    while time.time() - start_time < timeout:
        response = requests.get(
            f"http://localhost:8000/result/{job_id}/status",
            headers={"Authorization": f"Bearer {TOKEN}"}
        )

        if response.status_code != 200:
            raise Exception(f"Failed to check status: {response.status_code}")

        status_data = response.json()
        status = status_data["status"]

        if status == "completed":
            return True
        elif status == "failed":
            raise Exception(f"Processing failed: {status_data['error_message']}")

        time.sleep(poll_interval)

    raise TimeoutError(f"Job {job_id} did not complete within {timeout}s")


# Usage
response = requests.post("/process_pdf", files={"file": pdf})
job_id = response.json()["job_id"]

wait_for_completion(job_id)  # Blocks until done

# Now get results (same as before)
result = requests.get(f"/result/{job_id}/markdown")
markdown = result.json()["content"]
```

### Strategy 2: Async/Await (Modern Python)

Use asyncio for non-blocking operations:

```python
import asyncio
import aiohttp

async def process_pdf_async(pdf_path):
    """Process PDF asynchronously"""
    async with aiohttp.ClientSession() as session:
        # Upload
        with open(pdf_path, 'rb') as f:
            form = aiohttp.FormData()
            form.add_field('file', f, filename='doc.pdf')

            async with session.post(
                'http://localhost:8000/process_pdf',
                data=form,
                headers={'Authorization': f'Bearer {TOKEN}'}
            ) as resp:
                result = await resp.json()
                job_id = result['job_id']

        # Poll for completion
        while True:
            async with session.get(
                f'http://localhost:8000/result/{job_id}/status',
                headers={'Authorization': f'Bearer {TOKEN}'}
            ) as resp:
                status_data = await resp.json()
                status = status_data['status']

                if status == 'completed':
                    break
                elif status == 'failed':
                    raise Exception(status_data['error_message'])

                await asyncio.sleep(5)

        # Get results
        async with session.get(
            f'http://localhost:8000/result/{job_id}/markdown',
            headers={'Authorization': f'Bearer {TOKEN}'}
        ) as resp:
            result = await resp.json()
            return result['content']


# Usage
markdown = asyncio.run(process_pdf_async('document.pdf'))
```

### Strategy 3: Callback-Based (JavaScript/Node.js)

```javascript
const processPDF = async (pdfFile) => {
  // Upload
  const formData = new FormData();
  formData.append('file', pdfFile);

  const uploadResp = await fetch('http://localhost:8000/process_pdf', {
    method: 'POST',
    headers: { 'Authorization': `Bearer ${TOKEN}` },
    body: formData
  });
  const { job_id } = await uploadResp.json();

  // Poll for completion
  while (true) {
    const statusResp = await fetch(
      `http://localhost:8000/result/${job_id}/status`,
      { headers: { 'Authorization': `Bearer ${TOKEN}` } }
    );
    const { status, error_message } = await statusResp.json();

    if (status === 'completed') break;
    if (status === 'failed') throw new Error(error_message);

    await new Promise(resolve => setTimeout(resolve, 5000));
  }

  // Get results
  const resultResp = await fetch(
    `http://localhost:8000/result/${job_id}/markdown`,
    { headers: { 'Authorization': `Bearer ${TOKEN}` } }
  );
  const { content } = await resultResp.json();
  return content;
};
```

### Strategy 4: Event-Driven (Advanced)

For web applications, use WebSocket or Server-Sent Events (future enhancement):

```python
# Future API (not yet implemented)
@app.websocket("/ws/{job_id}")
async def websocket_status(websocket: WebSocket, job_id: str):
    await websocket.accept()
    while True:
        status = get_task_status(job_id)
        await websocket.send_json(status)
        if status["status"] in ["completed", "failed"]:
            break
        await asyncio.sleep(2)
    await websocket.close()
```

## Code Examples

### Python with Progress Bar

```python
import requests
import time
from tqdm import tqdm

def process_pdf_with_progress(pdf_path, token):
    """Process PDF with progress bar"""

    # Upload
    with open(pdf_path, 'rb') as f:
        response = requests.post(
            'http://localhost:8000/process_pdf',
            files={'file': f},
            headers={'Authorization': f'Bearer {token}'}
        )
    job_id = response.json()['job_id']
    print(f"Job ID: {job_id}")

    # Poll with progress
    pbar = None
    while True:
        response = requests.get(
            f'http://localhost:8000/result/{job_id}/status',
            headers={'Authorization': f'Bearer {token}'}
        )
        data = response.json()
        status = data['status']
        total = data.get('total_pages', 0)
        processed = data.get('processed_pages', 0)

        # Initialize progress bar when we know total pages
        if pbar is None and total > 0:
            pbar = tqdm(total=total, desc="Processing")

        # Update progress
        if pbar and processed > 0:
            pbar.n = processed
            pbar.refresh()

        # Check completion
        if status == 'completed':
            if pbar:
                pbar.close()
            print("✓ Processing complete!")
            break
        elif status == 'failed':
            if pbar:
                pbar.close()
            raise Exception(f"Failed: {data['error_message']}")

        time.sleep(3)

    # Get results
    response = requests.get(
        f'http://localhost:8000/result/{job_id}/markdown',
        headers={'Authorization': f'Bearer {token}'}
    )
    return response.json()['content']
```

### Batch Processing Multiple PDFs

```python
import requests
import time
from concurrent.futures import ThreadPoolExecutor, as_completed

def submit_pdf(pdf_path, token):
    """Submit PDF and return job_id"""
    with open(pdf_path, 'rb') as f:
        response = requests.post(
            'http://localhost:8000/process_pdf',
            files={'file': f},
            headers={'Authorization': f'Bearer {token}'}
        )
    return response.json()['job_id']


def wait_and_retrieve(job_id, token):
    """Wait for completion and retrieve results"""
    # Wait
    while True:
        response = requests.get(
            f'http://localhost:8000/result/{job_id}/status',
            headers={'Authorization': f'Bearer {token}'}
        )
        status = response.json()['status']

        if status == 'completed':
            break
        elif status == 'failed':
            return None

        time.sleep(5)

    # Retrieve
    response = requests.get(
        f'http://localhost:8000/result/{job_id}/markdown',
        headers={'Authorization': f'Bearer {token}'}
    )
    return response.json()['content']


def process_multiple_pdfs(pdf_paths, token, max_workers=5):
    """Process multiple PDFs concurrently"""

    # Submit all PDFs
    print(f"Submitting {len(pdf_paths)} PDFs...")
    job_ids = []
    for pdf_path in pdf_paths:
        job_id = submit_pdf(pdf_path, token)
        job_ids.append((pdf_path, job_id))
        print(f"  {pdf_path} → {job_id}")

    # Wait for all to complete
    print(f"\nWaiting for completion...")
    results = {}
    with ThreadPoolExecutor(max_workers=max_workers) as executor:
        futures = {
            executor.submit(wait_and_retrieve, job_id, token): pdf_path
            for pdf_path, job_id in job_ids
        }

        for future in as_completed(futures):
            pdf_path = futures[future]
            try:
                content = future.result()
                results[pdf_path] = content
                print(f"  ✓ {pdf_path}")
            except Exception as e:
                print(f"  ✗ {pdf_path}: {e}")
                results[pdf_path] = None

    return results


# Usage
pdfs = ['doc1.pdf', 'doc2.pdf', 'doc3.pdf']
results = process_multiple_pdfs(pdfs, TOKEN)
```

## Testing Your Migration

### 1. Update Your Test Suite

```python
import unittest
import requests

class TestAsyncAPI(unittest.TestCase):
    def test_process_pdf_returns_immediately(self):
        """Test that /process_pdf returns quickly"""
        start = time.time()

        with open('test.pdf', 'rb') as f:
            response = requests.post(
                'http://localhost:8000/process_pdf',
                files={'file': f}
            )

        elapsed = time.time() - start

        self.assertEqual(response.status_code, 200)
        self.assertLess(elapsed, 1.0, "Should return in less than 1 second")
        self.assertEqual(response.json()['status'], 'pending')

    def test_status_endpoint_exists(self):
        """Test that status endpoint works"""
        job_id = "test-job-id"
        response = requests.get(f'http://localhost:8000/result/{job_id}/status')
        self.assertIn(response.status_code, [200, 404])

    def test_result_endpoints_handle_pending(self):
        """Test that result endpoints return 202 for pending tasks"""
        # Submit PDF
        with open('test.pdf', 'rb') as f:
            response = requests.post(
                'http://localhost:8000/process_pdf',
                files={'file': f}
            )
        job_id = response.json()['job_id']

        # Try to get results immediately (should be 202)
        response = requests.get(f'http://localhost:8000/result/{job_id}/markdown')
        self.assertEqual(response.status_code, 202)
```

### 2. Use the Test Script

```bash
# Test with the provided script
python test_async_api.py your_test_document.pdf
```

## Rollback Plan

If you need to rollback to synchronous behavior temporarily:

```python
# Wrapper to make it synchronous (compatibility shim)
def process_pdf_sync(pdf_path, token, timeout=600):
    """Synchronous wrapper for backward compatibility"""
    with open(pdf_path, 'rb') as f:
        response = requests.post(
            'http://localhost:8000/process_pdf',
            files={'file': f},
            headers={'Authorization': f'Bearer {token}'}
        )

    job_id = response.json()['job_id']

    # Wait for completion
    start = time.time()
    while time.time() - start < timeout:
        response = requests.get(
            f'http://localhost:8000/result/{job_id}/status',
            headers={'Authorization': f'Bearer {token}'}
        )
        status = response.json()['status']

        if status == 'completed':
            # Return same format as old API
            return {
                'job_id': job_id,
                'status': 'completed',
                'message': 'PDF processed successfully'
            }
        elif status == 'failed':
            raise Exception(response.json()['error_message'])

        time.sleep(5)

    raise TimeoutError("Processing timeout")
```

## Benefits of Migration

✅ **Faster Response**: Upload endpoint returns in <100ms instead of minutes
✅ **Better UX**: Show progress to users
✅ **Concurrent Processing**: Process multiple PDFs simultaneously
✅ **Resilient**: Connection failures don't lose progress
✅ **Monitoring**: Track all jobs via `/tasks` endpoint
✅ **Error Handling**: Proper status codes and error messages

## Support

If you encounter issues during migration:

1. Check [API_GUIDE.md](API_GUIDE.md) for complete API documentation
2. Review [QUICK_REFERENCE.md](QUICK_REFERENCE.md) for examples
3. Run `python test_async_api.py` to verify the API works
4. Check server logs for detailed error messages

## Timeline Recommendation

- **Week 1**: Add polling logic to your client code
- **Week 2**: Test with production-like workloads
- **Week 3**: Deploy to staging environment
- **Week 4**: Roll out to production with monitoring

Good luck with your migration! 🚀
