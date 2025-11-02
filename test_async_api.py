#!/usr/bin/env python3
"""
Test script for the async PDF processing API
"""
import os
import time
import requests
from pathlib import Path

# Configuration
BASE_URL = "http://localhost:8000"
AUTH_TOKEN = os.getenv("AUTH_TOKEN", "")

# Headers
headers = {}
if AUTH_TOKEN:
    headers["Authorization"] = f"Bearer {AUTH_TOKEN}"


def test_async_processing(pdf_path: str):
    """Test the async PDF processing workflow"""
    print("=" * 60)
    print("Testing Async PDF Processing API")
    print("=" * 60)

    # 1. Submit PDF for processing
    print(f"\n1. Submitting PDF: {pdf_path}")
    with open(pdf_path, "rb") as f:
        files = {"file": f}
        response = requests.post(
            f"{BASE_URL}/process_pdf",
            files=files,
            headers=headers
        )

    if response.status_code != 200:
        print(f"❌ Failed to submit PDF: {response.status_code}")
        print(response.text)
        return

    result = response.json()
    job_id = result["job_id"]
    print(f"✅ PDF submitted successfully")
    print(f"   Job ID: {job_id}")
    print(f"   Status: {result['status']}")

    # 2. Poll for status
    print(f"\n2. Polling for status...")
    max_attempts = 60
    attempt = 0

    while attempt < max_attempts:
        response = requests.get(
            f"{BASE_URL}/result/{job_id}/status",
            headers=headers
        )

        if response.status_code != 200:
            print(f"❌ Failed to get status: {response.status_code}")
            break

        status_data = response.json()
        status = status_data["status"]
        total_pages = status_data.get("total_pages", 0)
        processed_pages = status_data.get("processed_pages", 0)

        print(f"   Attempt {attempt + 1}: {status}", end="")
        if total_pages > 0:
            print(f" ({processed_pages}/{total_pages} pages)")
        else:
            print()

        if status == "completed":
            print(f"✅ Processing completed!")
            print(f"   Filename: {status_data['filename']}")
            print(f"   Total pages: {status_data['total_pages']}")
            print(f"   Created at: {status_data['created_at']}")
            print(f"   Updated at: {status_data['updated_at']}")
            break
        elif status == "failed":
            print(f"❌ Processing failed!")
            print(f"   Error: {status_data['error_message']}")
            return

        time.sleep(5)
        attempt += 1

    if attempt >= max_attempts:
        print(f"⚠️  Timeout: Processing took too long")
        return

    # 3. Retrieve markdown result
    print(f"\n3. Retrieving markdown result...")
    response = requests.get(
        f"{BASE_URL}/result/{job_id}/markdown",
        headers=headers
    )

    if response.status_code == 200:
        result = response.json()
        content = result["content"]
        print(f"✅ Retrieved markdown content")
        print(f"   Length: {len(content)} characters")
        print(f"   Preview (first 200 chars):\n{content[:200]}...")
    elif response.status_code == 202:
        print(f"⚠️  Result not ready yet (HTTP 202)")
    else:
        print(f"❌ Failed to retrieve result: {response.status_code}")

    # 4. List extracted images
    print(f"\n4. Listing extracted images...")
    response = requests.get(
        f"{BASE_URL}/result/{job_id}/images",
        headers=headers
    )

    if response.status_code == 200:
        result = response.json()
        print(f"✅ Found {result['count']} extracted images")
        if result['count'] > 0:
            print(f"   Images: {', '.join(result['images'][:5])}")
            if result['count'] > 5:
                print(f"   ... and {result['count'] - 5} more")
    else:
        print(f"⚠️  No images found or error: {response.status_code}")

    # 5. List all tasks
    print(f"\n5. Listing all tasks...")
    response = requests.get(
        f"{BASE_URL}/tasks",
        headers=headers
    )

    if response.status_code == 200:
        result = response.json()
        print(f"✅ Found {result['count']} total tasks")
        for task in result['tasks'][:3]:
            print(f"   - {task['job_id'][:8]}... | {task['status']} | {task['filename']}")
        if result['count'] > 3:
            print(f"   ... and {result['count'] - 3} more")
    else:
        print(f"❌ Failed to list tasks: {response.status_code}")

    # 6. Optional: Clean up
    print(f"\n6. Clean up (optional)")
    cleanup = input(f"   Delete job {job_id[:8]}...? (y/N): ").strip().lower()

    if cleanup == 'y':
        response = requests.delete(
            f"{BASE_URL}/result/{job_id}",
            headers=headers
        )
        if response.status_code == 200:
            print(f"✅ Job deleted successfully")
        else:
            print(f"❌ Failed to delete job: {response.status_code}")
    else:
        print(f"   Job kept. Delete manually with: DELETE /result/{job_id}")

    print("\n" + "=" * 60)
    print("Test completed!")
    print("=" * 60)


if __name__ == "__main__":
    import sys

    if len(sys.argv) < 2:
        print("Usage: python test_async_api.py <pdf_file>")
        print("Example: python test_async_api.py sample.pdf")
        sys.exit(1)

    pdf_path = sys.argv[1]

    if not Path(pdf_path).exists():
        print(f"Error: File not found: {pdf_path}")
        sys.exit(1)

    if not pdf_path.endswith('.pdf'):
        print(f"Error: File must be a PDF: {pdf_path}")
        sys.exit(1)

    try:
        test_async_processing(pdf_path)
    except KeyboardInterrupt:
        print("\n\n⚠️  Test interrupted by user")
    except Exception as e:
        print(f"\n\n❌ Test failed with error: {e}")
        import traceback
        traceback.print_exc()
