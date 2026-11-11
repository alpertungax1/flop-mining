#!/usr/bin/env bash
# ==============================================================================
# Resolve and Bind Allowed Decode Policy from releases.json
# Fills DECODE_POLICY and DECODE_POLICY_HASH in the miner env file
# ==============================================================================
set -euo pipefail

ENV_FILE="${1:-/opt/flop-miner/miner-01.env}"

if [ ! -f "${ENV_FILE}" ]; then
  echo "[ERROR] Env file not found: ${ENV_FILE}"
  echo "Usage: sudo ./decode-policy.sh <path-to-miner.env>"
  exit 1
fi

MODEL_HASH=$(grep '^MODEL_HASH=' "${ENV_FILE}" | cut -d '=' -f2- | tr -d '"'"'")
if [ -z "${MODEL_HASH}" ] || [ "${MODEL_HASH}" = "0xREPLACE_WITH_REGISTERED_MODEL_HASH" ]; then
  echo "[ERROR] Please set a valid MODEL_HASH in ${ENV_FILE} first!"
  exit 1
fi

echo "==> Fetching releases.json from https://flop.network/releases.json..."
RELEASES_JSON=$(curl --fail --silent --show-error https://flop.network/releases.json)

POLICY_HASH=$(echo "${RELEASES_JSON}" | jq -r --arg HASH "${MODEL_HASH}" '.models[$HASH].decode_policies | keys[0] // empty')
if [ -z "${POLICY_HASH}" ]; then
  echo "[ERROR] No allowlisted decode policy found for model hash ${MODEL_HASH}"
  exit 1
fi

POLICY_JSON=$(echo "${RELEASES_JSON}" | jq -c --arg HASH "${MODEL_HASH}" --arg POL "${POLICY_HASH}" '.models[$HASH].decode_policies[$POL]')

echo "    Discovered Policy Hash: ${POLICY_HASH}"

sed -i "s|^DECODE_POLICY_HASH=.*|DECODE_POLICY_HASH=${POLICY_HASH}|" "${ENV_FILE}"
ESCAPED_JSON=$(printf '%s' "${POLICY_JSON}" | sed -e 's/[\/&]/\\&/g')
sed -i "s|^DECODE_POLICY=.*|DECODE_POLICY='${ESCAPED_JSON}'|" "${ENV_FILE}"

echo "==> Successfully bound DECODE_POLICY and DECODE_POLICY_HASH in ${ENV_FILE}."
