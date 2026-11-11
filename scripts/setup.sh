#!/usr/bin/env bash
# ==============================================================================
# FLOP Miner Initial Setup Script
# Creates directories and generates cryptographic seeds with strict 0600 permissions
# ==============================================================================
set -euo pipefail

BASE_DIR="/opt/flop-miner"

echo "==> Initializing FLOP miner directories under ${BASE_DIR}..."
sudo mkdir -p "${BASE_DIR}/models" "${BASE_DIR}/session-keys"
sudo chmod 700 "${BASE_DIR}/session-keys"

if [ ! -f "${BASE_DIR}/signer" ]; then
  echo "==> Generating dedicated sr25519 miner signer seed..."
  sudo sh -c 'umask 077; openssl rand -hex 32 > '"${BASE_DIR}/signer"
  sudo chown root:root "${BASE_DIR}/signer"
  sudo chmod 600 "${BASE_DIR}/signer"
  echo "    Miner signer seed created at ${BASE_DIR}/signer"
else
  echo "    [!] Signer file already exists at ${BASE_DIR}/signer, skipping creation."
fi

if [ ! -f "${BASE_DIR}/session-keys/enclave.seed" ]; then
  echo "==> Generating enclave session-signing seed..."
  sudo sh -c 'umask 077; openssl rand -hex 32 > '"${BASE_DIR}/session-keys/enclave.seed"
  sudo chown root:root "${BASE_DIR}/session-keys/enclave.seed"
  sudo chmod 600 "${BASE_DIR}/session-keys/enclave.seed"
  echo "    Enclave session seed created at ${BASE_DIR}/session-keys/enclave.seed"
else
  echo "    [!] Enclave seed already exists, skipping creation."
fi

echo "==> Setup complete. Please configure your miner-01.env file before proceeding."
