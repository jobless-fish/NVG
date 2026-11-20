"""Read-only local integration preflight. Never prints secrets or sends events."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import urllib.request
import urllib.error


def settings(path):
    values = {}
    if path.exists():
        for line in path.read_text(encoding="utf-8-sig").splitlines():
            key, sep, value = line.strip().partition("=")
            if sep and not key.startswith("#"):
                values[key.strip()] = value.strip().strip("\"'")
    return {**values, **os.environ}


def check(url, env_file):
    cfg = settings(env_file)
    key = cfg.get("INGEST_KEY", "")
    results = [{"check": "ingest_key_configured", "passed": len(key) >= 24 and not key.lower().startswith(("replace-", "change-"))}]
    for name, path in (("api_live", "/health/live"), ("kafka_ready", "/health/ready")):
        try:
            with urllib.request.urlopen(url.rstrip("/") + path, timeout=5) as response:
                body = json.load(response)
                passed = response.status == 200 and body.get("status") in ("ok", "ready")
        except Exception:
            passed = False
        results.append({"check": name, "passed": passed})
    try:
        with urllib.request.urlopen(url.rstrip("/") + "/openapi.json", timeout=5) as response:
            paths = json.load(response).get("paths", {})
            passed = all(path in paths for path in ("/v2/events", "/health/live", "/health/ready"))
    except Exception:
        passed = False
    results.append({"check": "v2_api_routes", "passed": passed})
    # Verify authentication with a deliberately invalid, non-production key and empty body.
    # Authentication must reject before schema validation, so this creates no Kafka/DLQ record.
    request = urllib.request.Request(url.rstrip("/") + "/v2/events", data=b"{}", headers={"Content-Type": "application/json", "X-API-Key": "preflight-invalid"})
    try:
        with urllib.request.urlopen(request, timeout=5):
            passed = False
    except urllib.error.HTTPError as exc:
        passed = exc.code == 401
    except Exception:
        passed = False
    results.append({"check": "invalid_key_rejected", "passed": passed})
    try:
        proc = subprocess.run(["docker", "info", "--format", "{{.ServerVersion}}"], capture_output=True, text=True, timeout=10)
        passed = proc.returncode == 0
    except (OSError, subprocess.TimeoutExpired):
        passed = False
    results.append({"check": "docker_engine", "passed": passed})
    return {"passed": all(item["passed"] for item in results), "checks": results,
            "scope": "Read-only preflight; does not prove Spark, Delta, MongoDB storage or dashboard integration."}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--url", default="http://127.0.0.1:8000")
    parser.add_argument("--env-file", type=Path, default=Path(__file__).with_name(".env"))
    args = parser.parse_args()
    report = check(args.url, args.env_file)
    print(json.dumps(report, ensure_ascii=False, indent=2))
    raise SystemExit(0 if report["passed"] else 1)


if __name__ == "__main__":
    main()
