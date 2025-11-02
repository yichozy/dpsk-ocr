# Architecture - Async PDF OCR Processing

## System Architecture

```
┌─────────────┐
│   Client    │
└──────┬──────┘
       │
       │ 1. POST /process_pdf (PDF file)
       ▼
┌─────────────────────────────────────────┐
│         FastAPI Server                  │
│  ┌────────────────────────────────────┐ │
│  │  POST /process_pdf Handler         │ │
│  │  - Validate PDF                    │ │
│  │  - Generate job_id                 │ │
│  │  - Save file to disk               │ │
│  │  - Create DB entry (pending)       │ │
│  │  - Queue background task           │ │
│  │  - Return job_id immediately       │ │
│  └────────────────────────────────────┘ │
└─────────────┬───────────────────────────┘
       │      │
       │      │ Background Task
       │      ▼
       │  ┌──────────────────────────────┐
       │  │  process_pdf_background()    │
       │  │  ┌──────────────────────────┐│
       │  │  │ Update: "processing"     ││
       │  │  ├──────────────────────────┤│
       │  │  │ PDF → Images             ││
       │  │  ├──────────────────────────┤│
       │  │  │ Update: total_pages      ││
       │  │  ├──────────────────────────┤│
       │  │  │ Run OCR (vLLM)           ││
       │  │  ├──────────────────────────┤│
       │  │  │ Process Results          ││
       │  │  ├──────────────────────────┤│
       │  │  │ Save Outputs             ││
       │  │  ├──────────────────────────┤│
       │  │  │ Update: "completed"      ││
       │  │  └──────────────────────────┘│
       │  └──────────────────────────────┘
       │                │
       │ 2. Response    │ Updates
       │    (job_id,    │
       │     pending)   ▼
       ▼         ┌──────────────────┐
┌─────────────┐ │  SQLite Database │
│   Client    │ │                  │
│             │ │  ┌─────────────┐ │
│  Stores     │ │  │   Tasks     │ │
│  job_id     │ │  ├─────────────┤ │
└──────┬──────┘ │  │ job_id  PK  │ │
       │        │  │ status      │ │
       │        │  │ filename    │ │
       │        │  │ total_pages │ │
       │        │  │ proc_pages  │ │
       │        │  │ created_at  │ │
       │        │  │ updated_at  │ │
       │        │  │ error_msg   │ │
       │ 3. GET │  └─────────────┘ │
       │ /status│                  │
       ▼        └──────────────────┘
┌─────────────────────────────────┐
│  GET /result/{job_id}/status    │
│  - Query database               │
│  - Return task info             │
│  - Status: pending/processing/  │
│    completed/failed             │
└─────────────┬───────────────────┘
       │
       │ 4. Response (status info)
       ▼
┌─────────────┐
│   Client    │
│             │
│  If status  │
│  == pending │──┐
│  or         │  │
│  processing │  │
│             │  │
│  Wait 5s    │  │
│  Go to #3 ──┘  │
│             │  │
│  If status  │  │
│  == failed  │  │
│  Show error │  │
│             │  │
│  If status  │  │
│  == done    │  │
│  ▼          │  │
└──────┬──────┘  │
       │         │
       │ 5. GET  │
       │ /markdown│
       ▼         │
┌─────────────────────────────────┐
│  GET /result/{job_id}/markdown  │
│  - Check status in DB           │
│  - If not completed: HTTP 202   │
│  - If completed: read file      │
│  - Return content               │
└─────────────┬───────────────────┘
       │
       │ 6. Response (markdown)
       ▼
┌─────────────┐
│   Client    │
│             │
│  Process    │
│  results    │
└─────────────┘
```

## Data Flow

### 1. Task Creation Phase

```
User → FastAPI → File System → Database
                     ↓              ↓
                 tmp/pdf_ocr/   tasks table
                   {job_id}/    (status: pending)
```

### 2. Background Processing Phase

```
Background Task
    ↓
Convert PDF to Images
    ↓
Update DB (status: processing, total_pages: N)
    ↓
Parallel Image Processing (ThreadPoolExecutor)
    ↓
Batch OCR Inference (vLLM)
    ↓
Process & Save Results
    ├── output.mmd (markdown)
    ├── output_det.mmd (markdown with detection)
    ├── output_layouts.pdf (layout visualization)
    └── images/ (extracted images)
    ↓
Update DB (status: completed, processed_pages: N)
```

### 3. Status Polling Phase

```
Client Poll Loop:
    ┌──────────────────────┐
    │ GET /status          │
    ├──────────────────────┤
    │ Response: pending?   │───Yes──> Wait 5s ──┐
    │                      │                    │
    │ Response: processing?│───Yes──> Wait 5s ──┤
    │                      │                    │
    │ Response: completed? │───Yes──> Get Results
    │                      │
    │ Response: failed?    │───Yes──> Show Error
    └──────────────────────┘
                                        ↑
                                        │
                                  Poll again
```

## Component Responsibilities

### FastAPI Application (`serve_pdf.py`)
- **Request Handling**: Receive HTTP requests, validate inputs
- **Authentication**: Verify Bearer tokens
- **Task Management**: Create tasks, queue background jobs
- **Response Generation**: Return JSON/file responses
- **Error Handling**: Catch exceptions, return appropriate HTTP codes

### Database Module (`database.py`)
- **Persistence**: Store task metadata in SQLite
- **CRUD Operations**: Create, Read, Update, Delete tasks
- **Thread Safety**: Thread-local connections for concurrent access
- **Querying**: Filter tasks by status, list all tasks

### Background Processing
- **PDF Conversion**: Convert PDF pages to high-quality images
- **OCR Inference**: Run DeepSeek OCR model via vLLM
- **Result Processing**: Extract text, images, layout information
- **File I/O**: Save outputs to disk
- **Status Updates**: Update database throughout process

### File System (`tmp/pdf_ocr/`)
```
tmp/pdf_ocr/
├── {job_id_1}/
│   ├── input.pdf
│   ├── output.mmd
│   ├── output_det.mmd
│   ├── output_layouts.pdf
│   └── images/
│       ├── 0_0.jpg
│       ├── 0_1.jpg
│       └── 1_0.jpg
├── {job_id_2}/
│   └── ...
└── {job_id_3}/
    └── ...
```

## Concurrency Model

### Request Level
```
FastAPI async handlers
    ↓
Multiple concurrent HTTP requests OK
    ↓
Each request gets its own event loop task
```

### Processing Level
```
Background Task Queue (FastAPI BackgroundTasks)
    ↓
Sequential task execution (one at a time)
    ↓
Within each task:
    ├── PDF conversion: Sequential
    ├── Image preprocessing: Parallel (ThreadPoolExecutor)
    └── OCR inference: Batch processing (vLLM)
```

### Database Level
```
Thread-local SQLite connections
    ↓
Each thread/task gets its own connection
    ↓
No lock contention between readers/writers
```

## State Transitions

```
       [Task Created]
            │
            ▼
     ┌─[PENDING]─┐
     │           │
     │  Queued   │
     │           │
     └─────┬─────┘
           │
           ▼
    ┌─[PROCESSING]─┐
    │              │
    │  Converting  │
    │  Running OCR │
    │  Saving      │
    │              │
    └──┬────────┬──┘
       │        │
   Success   Failure
       │        │
       ▼        ▼
 [COMPLETED] [FAILED]
       │        │
    Results   Error
  Available  Message
```

## Error Handling Flow

```
Exception in process_pdf_background()
    ↓
Caught by try/except wrapper
    ↓
update_task_status(job_id, "failed", error_message=str(e))
    ↓
Client polls /status
    ↓
Receives status: "failed" + error_message
    ↓
Client displays error to user
```

## Performance Characteristics

### Timeline for Processing a 10-page PDF:

```
T=0ms     POST /process_pdf
            ├─ Validate file (~5ms)
            ├─ Save to disk (~20ms)
            ├─ Create DB entry (~2ms)
            ├─ Queue background task (~1ms)
            └─ Return response (~2ms)
T=30ms    Response received by client

T=30ms    Background task starts
            ├─ Update status to processing (~2ms)
            ├─ PDF → Images (~10s)
            ├─ Preprocess images (~5s)
            ├─ OCR inference (~60s)
            ├─ Process results (~3s)
            └─ Save outputs (~2s)
T=80s     Status becomes "completed"

Client polls every 5s:
  T=0s:   pending
  T=5s:   processing (2/10 pages)
  T=10s:  processing (4/10 pages)
  T=15s:  processing (6/10 pages)
  ...
  T=80s:  completed
```

## Scalability Considerations

### Current Limits
- **Concurrent OCR jobs**: 1 (sequential background tasks)
- **Concurrent preprocessing**: `NUM_WORKERS` threads
- **vLLM batch size**: `MAX_CONCURRENCY` images
- **Database connections**: 1 per thread (thread-local)

### Scaling Options
1. **Multiple Workers**: Deploy multiple server instances
2. **Task Queue**: Replace BackgroundTasks with Celery/RQ
3. **Distributed Storage**: Replace SQLite with PostgreSQL
4. **Object Storage**: Store files in S3/MinIO instead of local disk
5. **Load Balancer**: Distribute requests across workers

## Security Architecture

```
Request → HTTPBearer Middleware
            ↓
     Token validation
            ↓
     ✓ Valid token → Process request
     ✗ Invalid token → HTTP 401
            ↓
     Job ID → Database lookup
            ↓
     ✓ Job exists → Return data
     ✗ No job → HTTP 404
```

## Monitoring Points

1. **Health Endpoint**: `/health` - Model availability
2. **Task Status**: `/tasks` - Active/pending/failed jobs
3. **Database**: Query `tasks` table for statistics
4. **File System**: Monitor `tmp/pdf_ocr/` disk usage
5. **Logs**: Server console output for errors

## Cleanup Strategy

### Automatic (Future Enhancement)
```python
@app.on_event("startup")
async def cleanup_old_tasks():
    """Run daily cleanup"""
    scheduler.add_job(
        cleanup_old_tasks,
        'interval',
        days=1,
        args=[7]  # Delete tasks older than 7 days
    )
```

### Manual
```bash
# Delete old database entries
python -c "from database import cleanup_old_tasks; cleanup_old_tasks(7)"

# Delete old files
find tmp/pdf_ocr -type d -mtime +7 -exec rm -rf {} +
```
