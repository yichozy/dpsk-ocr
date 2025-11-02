# DeepSeek OCR PDF Service - API Guide

## Overview

This service provides asynchronous PDF OCR processing with task tracking. The `/process_pdf` endpoint now returns immediately with a task ID, allowing you to check the processing status separately.

## Database

Tasks are tracked in a SQLite database (`task_status.db`) with the following schema:

- `job_id`: Unique identifier for the task
- `status`: Current status (pending, processing, completed, failed)
- `created_at`: Task creation timestamp
- `updated_at`: Last update timestamp
- `error_message`: Error details if failed
- `filename`: Original uploaded filename
- `total_pages`: Total number of pages in PDF
- `processed_pages`: Number of pages processed so far

## Endpoints

### 1. Process PDF (Async)

**Endpoint:** `POST /process_pdf`

**Description:** Upload a PDF file for processing. Returns immediately with a task ID.

**Request:**
```bash
curl -X POST "http://localhost:8000/process_pdf" \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -F "file=@your_document.pdf"
```

**Response:**
```json
{
  "job_id": "123e4567-e89b-12d3-a456-426614174000",
  "status": "pending",
  "message": "PDF processing initiated. Use /result/{job_id}/status to check progress."
}
```

### 2. Check Task Status

**Endpoint:** `GET /result/{job_id}/status`

**Description:** Check the current processing status of a task.

**Request:**
```bash
curl "http://localhost:8000/result/{job_id}/status" \
  -H "Authorization: Bearer YOUR_TOKEN"
```

**Response:**
```json
{
  "job_id": "123e4567-e89b-12d3-a456-426614174000",
  "status": "processing",
  "filename": "document.pdf",
  "total_pages": 10,
  "processed_pages": 5,
  "created_at": "2025-11-01T10:00:00",
  "updated_at": "2025-11-01T10:02:30",
  "error_message": null
}
```

**Status Values:**
- `pending`: Task created, not yet started
- `processing`: PDF is being processed
- `completed`: Processing finished successfully
- `failed`: Processing failed (check error_message)

### 3. Get Markdown Result

**Endpoint:** `GET /result/{job_id}/markdown`

**Description:** Retrieve the processed markdown content (without detection annotations).

**Request:**
```bash
curl "http://localhost:8000/result/{job_id}/markdown" \
  -H "Authorization: Bearer YOUR_TOKEN"
```

**Response:**
```json
{
  "job_id": "123e4567-e89b-12d3-a456-426614174000",
  "status": "completed",
  "content": "# Document Title\n\nContent here..."
}
```

**Error Responses:**
- `202 Accepted`: Processing not started yet or still in progress
- `404 Not Found`: Job ID not found
- `500 Internal Server Error`: Processing failed

### 4. Get Markdown with Detection

**Endpoint:** `GET /result/{job_id}/markdown_det`

**Description:** Retrieve markdown with layout detection annotations.

**Request:**
```bash
curl "http://localhost:8000/result/{job_id}/markdown_det" \
  -H "Authorization: Bearer YOUR_TOKEN"
```

**Response:** Same format as `/markdown` endpoint.

### 5. Download Layout PDF

**Endpoint:** `GET /result/{job_id}/layout_pdf`

**Description:** Download the PDF with layout visualizations (bounding boxes).

**Request:**
```bash
curl "http://localhost:8000/result/{job_id}/layout_pdf" \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -o layout.pdf
```

**Response:** PDF file download

### 6. List Extracted Images

**Endpoint:** `GET /result/{job_id}/images`

**Description:** List all images extracted from the PDF.

**Request:**
```bash
curl "http://localhost:8000/result/{job_id}/images" \
  -H "Authorization: Bearer YOUR_TOKEN"
```

**Response:**
```json
{
  "job_id": "123e4567-e89b-12d3-a456-426614174000",
  "status": "completed",
  "images": ["0_0.jpg", "0_1.jpg", "1_0.jpg"],
  "count": 3
}
```

### 7. Get Specific Image

**Endpoint:** `GET /result/{job_id}/images/{image_name}`

**Description:** Download a specific extracted image.

**Request:**
```bash
curl "http://localhost:8000/result/{job_id}/images/0_0.jpg" \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -o image.jpg
```

**Response:** JPEG image file download

### 8. List All Tasks

**Endpoint:** `GET /tasks`

**Description:** List all tasks, optionally filtered by status.

**Request:**
```bash
# List all tasks
curl "http://localhost:8000/tasks" \
  -H "Authorization: Bearer YOUR_TOKEN"

# Filter by status
curl "http://localhost:8000/tasks?status=completed" \
  -H "Authorization: Bearer YOUR_TOKEN"
```

**Response:**
```json
{
  "tasks": [
    {
      "job_id": "123e4567-e89b-12d3-a456-426614174000",
      "status": "completed",
      "filename": "document1.pdf",
      "total_pages": 10,
      "processed_pages": 10,
      "created_at": "2025-11-01T10:00:00",
      "updated_at": "2025-11-01T10:05:00",
      "error_message": null
    },
    {
      "job_id": "234e5678-e89b-12d3-a456-426614174001",
      "status": "processing",
      "filename": "document2.pdf",
      "total_pages": 5,
      "processed_pages": 3,
      "created_at": "2025-11-01T10:10:00",
      "updated_at": "2025-11-01T10:12:00",
      "error_message": null
    }
  ],
  "count": 2
}
```

### 9. Delete Task

**Endpoint:** `DELETE /result/{job_id}`

**Description:** Delete all files and database entries for a task.

**Request:**
```bash
curl -X DELETE "http://localhost:8000/result/{job_id}" \
  -H "Authorization: Bearer YOUR_TOKEN"
```

**Response:**
```json
{
  "job_id": "123e4567-e89b-12d3-a456-426614174000",
  "status": "deleted"
}
```

## Typical Workflow

1. **Submit PDF for processing:**
   ```bash
   JOB_ID=$(curl -X POST "http://localhost:8000/process_pdf" \
     -H "Authorization: Bearer YOUR_TOKEN" \
     -F "file=@document.pdf" | jq -r '.job_id')
   ```

2. **Poll for status until completed:**
   ```bash
   while true; do
     STATUS=$(curl "http://localhost:8000/result/$JOB_ID/status" \
       -H "Authorization: Bearer YOUR_TOKEN" | jq -r '.status')
     echo "Status: $STATUS"
     if [ "$STATUS" = "completed" ] || [ "$STATUS" = "failed" ]; then
       break
     fi
     sleep 5
   done
   ```

3. **Retrieve results:**
   ```bash
   curl "http://localhost:8000/result/$JOB_ID/markdown" \
     -H "Authorization: Bearer YOUR_TOKEN" > result.json
   ```

## Error Handling

All result endpoints (`/markdown`, `/markdown_det`, `/layout_pdf`, `/images`) now check the task status first:

- **HTTP 202 Accepted**: Task is still pending or processing. Wait and retry.
- **HTTP 404 Not Found**: Job ID doesn't exist in the database.
- **HTTP 500 Internal Server Error**: Processing failed. Check the `error_message` field from `/status` endpoint.

## Authentication

If `AUTH_TOKEN` is set in the environment, all requests must include:
```
Authorization: Bearer YOUR_TOKEN_HERE
```

If `AUTH_TOKEN` is not set, authentication is disabled.

## Health Check

**Endpoint:** `GET /health`

Check if the service is running and the model is loaded:

```bash
curl "http://localhost:8000/health"
```

**Response:**
```json
{
  "status": "healthy",
  "model_loaded": true
}
```
