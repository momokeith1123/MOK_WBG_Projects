import requests
import pandas as pd
import time

# ──────────────────────────────────────────────
# CONFIGURATION
# ──────────────────────────────────────────────
BASE_URL = "https://findata-qa.worldbank.org:9047"
TOKEN = "2kyYvdyKQQyvBOaXoeo6ajDuKR3bd9BDoVnvO3In3xd+sZf03MUwQpFm7v2C7A=="

SQL_QUERY = 'SELECT * FROM publishFINDATAREP.IFCTRE.Application.Murex."Perf_Benchmark_Weights" LIMIT 10'

HEADERS = {
    "Authorization": f"_dremio{TOKEN}",
    "Content-Type": "application/json"
}


def test_query():
    print("=" * 50)
    print("DREMIO CONNECTION TEST")
    print("=" * 50)

    # ── Step 1: Submit job ──
    print(f"\n[1] Submitting query:\n    {SQL_QUERY}\n")
    try:
        response = requests.post(
            f"{BASE_URL}/api/v3/sql",
            headers=HEADERS,
            json={"sql": SQL_QUERY},
            verify=True,
            timeout=30
        )
        response.raise_for_status()
        job_id = response.json().get("id")
        print(f"    Job ID: {job_id}")
    except requests.exceptions.HTTPError as e:
        print(f"    ERROR submitting job: {e}")
        print(f"    Response: {response.text}")
        return
    except requests.exceptions.ConnectionError:
        print("    ERROR: Could not connect to Dremio. Check the host/port or your VPN.")
        return

    # ── Step 2: Poll for completion ──
    print("\n[2] Waiting for job to complete...")
    url = f"{BASE_URL}/api/v3/job/{job_id}"
    for attempt in range(30):  # max 60 seconds
        response = requests.get(url, headers=HEADERS, verify=True)
        response.raise_for_status()
        status = response.json().get("jobState")
        print(f"    Attempt {attempt + 1}: {status}")

        if status == "COMPLETED":
            break
        elif status in ("FAILED", "CANCELED"):
            error_msg = response.json().get("errorMessage", "No details available.")
            print(f"\n    ERROR: Job {status}.")
            print(f"    Details: {error_msg}")
            return
        time.sleep(2)
    else:
        print("\n    ERROR: Job timed out after 60 seconds.")
        return

    # ── Step 3: Fetch results ──
    print("\n[3] Fetching results...")
    response = requests.get(
        f"{BASE_URL}/api/v3/job/{job_id}/results?offset=0&limit=10",
        headers=HEADERS,
        verify=True
    )
    response.raise_for_status()
    data = response.json()

    columns = [col["name"] for col in data.get("schema", [])]
    rows = data.get("rows", [])

    df = pd.DataFrame(rows, columns=columns)

    # ── Step 4: Print summary ──
    print("\n" + "=" * 50)
    print("TEST RESULTS")
    print("=" * 50)
    print(f"  Rows returned : {len(df)}")
    print(f"  Columns       : {len(df.columns)}")
    print(f"  Column names  : {list(df.columns)}")
    print("\nSample data (first 5 rows):")
    print(df.head())
    print("\n TEST PASSED — Connection and query are working correctly.")


if __name__ == "__main__":
    test_query()
