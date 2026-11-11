#!/usr/bin/env bash
# ==============================================================================
# Devnet Stake Sponsorship Request Script
# Signs a sponsor payload with the miner key and POSTs to the faucet endpoint
# ==============================================================================
set -euo pipefail

SPONSOR_URL="${SPONSOR_URL:-https://faucet.flop.network}"
FLOP_RPC="${FLOP_RPC:-wss://rpc.devnet.flop.network}"
SIGNER_FILE="${MINER_SIGNER_FILE:-/opt/flop-miner/signer}"
FLOP_CLI="${FLOP_CLI:-ghcr.io/flop-labs/flop-core/cli:stable}"

if [ ! -f "${SIGNER_FILE}" ]; then
  echo "[ERROR] Signer file not found at ${SIGNER_FILE}"
  exit 1
fi

echo "==> Requesting FLOP devnet stake sponsorship from ${SPONSOR_URL}..."

MINER_SECRET="$(sudo cat "${SIGNER_FILE}")"
MINER_ADDRESS=$(docker run --rm --network host -e MINER_SECRET "${FLOP_CLI}" \
  keys inspect --type sr25519 --secret-env MINER_SECRET --output-type json | jq -r .address)

echo "    Miner Address: ${MINER_ADDRESS}"

TIMESTAMP=$(date +%s%3N)
GENESIS_HASH=$(docker run --rm --network host "${FLOP_CLI}" --network devnet --rpc "${FLOP_RPC}" network status --json | jq -r .genesisHash)
PAYLOAD="flop-sponsor/v1|miner|${GENESIS_HASH}|${MINER_ADDRESS}|${TIMESTAMP}"

echo "    Signing sponsorship payload..."
SIGNATURE=$(docker run --rm --network host -e MINER_SECRET "${FLOP_CLI}" \
  keys sign --type sr25519 --secret-env MINER_SECRET --message "${PAYLOAD}")

echo "    Submitting request to faucet..."
HTTP_STATUS=$(curl -s -o /tmp/sponsor_resp.json -w "%{http_code}" -X POST "${SPONSOR_URL}/sponsor/miner" \
  -H "Content-Type: application/json" \
  -d "{\"address\": \"${MINER_ADDRESS}\", \"issuedAt\": ${TIMESTAMP}, \"signature\": \"${SIGNATURE}\"}")

if [ "${HTTP_STATUS}" -eq 200 ] || [ "${HTTP_STATUS}" -eq 201 ]; then
  echo "[SUCCESS] Sponsorship granted! Account registered with sponsored stake."
  cat /tmp/sponsor_resp.json
elif [ "${HTTP_STATUS}" -eq 429 ]; then
  echo "[429] Automatic sponsorship quota full (max 100 concurrent uncalibrated miners). Retry shortly once an existing miner calibrates."
else
  echo "[FAILED] HTTP ${HTTP_STATUS}"
  cat /tmp/sponsor_resp.json
  exit 1
fi
