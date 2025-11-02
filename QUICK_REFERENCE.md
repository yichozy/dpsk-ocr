# Quick Reference - Async PDF OCR API

## Quick Start

### 1. Submit PDF for Processing
```bash
curl -X POST "http://localhost:8000/process_pdf" \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -F "file=@document.pdf"
```
**Response:**
```json
{"job_id": "abc-123", "status": "pending", "message": "..."}
```

### 2. Check Status
```bash
curl "http://localhost:8000/result/abc-123/status" \
  -H "Authorization: Bearer YOUR_TOKEN"
```
**Response:**
```json
{
  "job_id": "abc-123",
  "status": "processing",
  "filename": "document.pdf",
  "total_pages": 10,
  "processed_pages": 5,
  "created_at": "2025-11-01T10:00:00",
  "updated_at": "2025-11-01T10:02:30",
  "error_message": null
}
```

### 3. Get Results (when status = "completed")
```bash
# Markdown content
curl "http://localhost:8000/result/abc-123/markdown" \
  -H "Authorization: Bearer YOUR_TOKEN"

# Layout PDF with bounding boxes
curl "http://localhost:8000/result/abc-123/layout_pdf" \
  -H "Authorization: Bearer YOUR_TOKEN" -o layout.pdf

# List extracted images
curl "http://localhost:8000/result/abc-123/images" \
  -H "Authorization: Bearer YOUR_TOKEN"
```

## All Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/process_pdf` | Submit PDF (returns immediately) |
| GET | `/result/{job_id}/status` | Check processing status |
| GET | `/result/{job_id}/markdown` | Get markdown content |
| GET | `/result/{job_id}/markdown_det` | Get markdown with detection |
| GET | `/result/{job_id}/layout_pdf` | Download layout PDF |
| GET | `/result/{job_id}/images` | List extracted images |
| GET | `/result/{job_id}/images/{name}` | Download specific image |
| GET | `/tasks` | List all tasks |
| GET | `/tasks?status=processing` | Filter tasks by status |
| DELETE | `/result/{job_id}` | Delete task and files |
| GET | `/health` | Health check |

## Task Status Values

- **pending**: Task created, not started yet
- **processing**: Currently processing PDF
- **completed**: All done, results available
- **failed**: Error occurred (see error_message)

## HTTP Status Codes

- **200**: Success, data returned
- **202**: Accepted, still processing (wait and retry)
- **404**: Job not found
- **500**: Processing failed

## Python Example

```python
import requests
import time

# 1. Submit PDF
response = requests.post(
    "http://localhost:8000/process_pdf",
    files={"file": open("doc.pdf", "rb")},
    headers={"Authorization": "Bearer YOUR_TOKEN"}
)
job_id = response.json()["job_id"]
print(f"Job ID: {job_id}")

# 2. Wait for completion
while True:
    status_resp = requests.get(
        f"http://localhost:8000/result/{job_id}/status",
        headers={"Authorization": "Bearer YOUR_TOKEN"}
    )
    status = status_resp.json()["status"]
    print(f"Status: {status}")

    if status == "completed":
        break
    elif status == "failed":
        print("Error:", status_resp.json()["error_message"])
        exit(1)

    time.sleep(5)

# 3. Get results
result_resp = requests.get(
    f"http://localhost:8000/result/{job_id}/markdown",
    headers={"Authorization": "Bearer YOUR_TOKEN"}
)
markdown = result_resp.json()["content"]
print(markdown)
```

## JavaScript Example

```javascript
// 1. Submit PDF
const formData = new FormData();
formData.append('file', pdfFile);

const submitResp = await fetch('http://localhost:8000/process_pdf', {
  method: 'POST',
  headers: { 'Authorization': 'Bearer YOUR_TOKEN' },
  body: formData
});
const { job_id } = await submitResp.json();
console.log('Job ID:', job_id);

// 2. Poll for completion
while (true) {
  const statusResp = await fetch(
    `http://localhost:8000/result/${job_id}/status`,
    { headers: { 'Authorization': 'Bearer YOUR_TOKEN' } }
  );
  const { status } = await statusResp.json();
  console.log('Status:', status);

  if (status === 'completed') break;
  if (status === 'failed') throw new Error('Processing failed');

  await new Promise(resolve => setTimeout(resolve, 5000));
}

// 3. Get results
const resultResp = await fetch(
  `http://localhost:8000/result/${job_id}/markdown`,
  { headers: { 'Authorization': 'Bearer YOUR_TOKEN' } }
);
const { content } = await resultResp.json();
console.log(content);
```

## Database

Tasks are stored in `task_status.db` (SQLite):

```sql
-- View all tasks
SELECT job_id, status, filename, total_pages, created_at
FROM tasks
ORDER BY created_at DESC;

-- Count by status
SELECT status, COUNT(*)
FROM tasks
GROUP BY status;

-- Clean up old tasks
DELETE FROM tasks
WHERE created_at < datetime('now', '-7 days');
```

## Testing

```bash
# Start server
python serve_pdf.py

# Test with sample PDF
python test_async_api.py sample.pdf
```

## Troubleshooting

**Problem:** "Job not found" error
- **Solution**: Job ID may be invalid or task was deleted

**Problem:** HTTP 202 for long time
- **Solution**: Processing takes time. Keep polling. Check `/status` for progress.

**Problem:** Status stuck at "pending"
- **Solution**: Check server logs. Background task may not have started.

**Problem:** Status shows "failed"
- **Solution**: Check error_message field in `/status` response

## Tips

- Poll `/status` every 3-5 seconds (don't spam)
- Check `total_pages` and `processed_pages` for progress estimation
- Use `/tasks` to monitor all ongoing jobs
- Delete completed jobs to save disk space
- Set AUTH_TOKEN environment variable for security
