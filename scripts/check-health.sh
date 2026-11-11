#!/usr/bin/env bash
# ==============================================================================
# Health Check and Diagnostics Probe for FLOP Miner
# Checks internal backend /health and worker /session/info
# ==============================================================================
set -euo pipefail

ENV_FILE="${1:-/opt/flop-miner/miner-01.env}"
if [ -f "${ENV_FILE}" ]; then
  # shellcheck source=/dev/null
  set -a && source "${ENV_FILE}" && set +a
fi

echo "=================================================="
echo " 1. Checking GPU vLLM Backend Health..."
echo "=================================================="
if command -v docker >/dev/null 2>&1; then
  docker compose exec -T backend python3 -c '
import os, urllib.request, json
key = os.environ.get("INFERENCE_API_KEY", "")
try:
    req = urllib.request.Request("http://127.0.0.1:8000/health", headers={"Authorization": f"Bearer {key}"})
    with urllib.request.urlopen(req) as resp:
        data = json.loads(resp.read().decode())
        print(f"  [OK] Backend Status: {data.get(\"status\", \"OK\")}")
        print(f"  [OK] Model Identity: {data.get(\"model_identity\")}")
        print(f"  [OK] Model Hash:     {data.get(\"model_hash\")}")
        print(f"  [OK] Policy Hash:    {data.get(\"decode_policy_hash\")}")
except Exception as e:
    print(f"  [FAIL] Backend /health query failed: {e}")
' || true
fi

echo ""
echo "=================================================="
echo " 2. Checking Worker Session Status..."
echo "=================================================="
SESSION_HOST="${SESSION_PUBLIC_HOST:-localhost}"
SESSION_TOKEN="${SESSION_AUTH_TOKEN:-}"

if [ -n "${SESSION_TOKEN}" ]; then
  curl --fail --silent --show-error \
    -H "Authorization: Bearer ${SESSION_TOKEN}" \
    "https://${SESSION_HOST}/session/info" | jq '{minerAddress, modelHash, calibration, is_ready}' || true
else
  echo "[!] SESSION_AUTH_TOKEN not provided; skipping session/info probe."
fi
