# FLOP Network GPU Miner (`flop-mining`)

[![FLOP Network Docs](https://img.shields.io/badge/FLOP%20Docs-run--miner-blue)](https://docs.flop.network/docs/run-miner)
[![Docker](https://img.shields.io/badge/Docker-Compose%20v2-2496ED?logo=docker&logoColor=white)](https://docs.docker.com/)
[![NVIDIA](https://img.shields.io/badge/NVIDIA-CUDA%20%7C%20vLLM-76B900?logo=nvidia&logoColor=white)](https://www.nvidia.com/)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

Comprehensive setup guide, production Docker Compose templates, and automation scripts for deploying a **FLOP Network AI Inference Miner** on an NVIDIA GPU host.

> **Dil Seçimi / Language Selection**:
> - [🇹🇷 Türkçe Kurulum ve İşletim Rehberi](#-türkçe-kurulum-ve-i̇şletim-rehberi)
> - [🇬🇧 English Setup & Operations Guide](#-english-setup--operations-guide)

---

## Architecture Overview / Mimari Genel Bakış

FLOP Network is a decentralized AI inference compute protocol utilizing **TOPLOC** (Topological Locality Proofs) for cryptographic proof of genuine model execution. A standard GPU host runs a synchronized dual-service pair:

```
                  +--------------------------------------------------+
                  |                 INTERNET / GATEWAY               |
                  +--------------------------------------------------+
                                           | HTTPS (80, 443)
                                           v
+--------------------------------------------------------------------+
|  GPU Host                                                          |
|                                                                    |
|  +--------------------+         HTTP          +-----------------+  |
|  | Caddy (TLS Sidecar)| --------------------> |  miner-worker   |  |
|  +--------------------+   (127.0.0.1:8645)    |  (CPU Engine)   |  |
|                                               +-----------------+  |
|                                                        |           |
|                                                        | HTTP      |
|                                                        | (Port     |
|                                                        |  8000)    |
|                                                        v           |
|                                               +-----------------+  |
|                                               | miner-vllm-     |  |
|                                               | toploc (GPU)    |  |
|                                               +-----------------+  |
|                                                        |           |
|                                                        v           |
|                                                [ NVIDIA GPU(s) ]   |
+--------------------------------------------------------------------+
```

1. **`miner-worker` (CPU Service)**:
   - Signs on-chain transactions using dedicated `sr25519` keypair.
   - Manages compute-channel sessions and answers ghost calibration tasks.
   - Publishes TOPLOC cryptographic evidence and signs endpoint advertisements.
2. **`miner-vllm-toploc` (GPU Backend Service)**:
   - High-throughput vLLM inference backend running in verified BF16 precision.
   - Generates deterministic execution traces and TOPLOC proofs on the physical GPU.
   - Private and isolated on host/internal network (port 8000).
3. **`caddy` (Automated TLS Sidecar)**:
   - Listens on public ports 80/443 with automated Let's Encrypt certificates.
   - Forwards authenticated session traffic to `127.0.0.1:8645`.

---

# 🇹🇷 TÜRKÇE KURULUM VE İŞLETİM REHBERİ

## 1. Donanım ve Sistem Gereksinimleri

* **İşletim Sistemi**: Ubuntu 22.04 veya 24.04 LTS (x86_64).
* **GPU**: Minimum 16 GB - 24 GB+ VRAM'e sahip NVIDIA ekran kartı (Resmi devnet testi **NVIDIA A40** ile doğrulanmıştır; RTX 3090, RTX 4090, A5000, A6000, A100, H100 uyumludur).
* **Depolama**: Minimum 60–100 GB NVMe/SSD boş disk alanı.
* **Ağ**: Statik IP ve sunucuya yönlendirilmiş DNS kaydı (örn: `miner.alanadiniz.com`). 80 ve 443 portları açık olmalıdır.
* **Yazılımlar**: Docker Engine 24+, Docker Compose v2, NVIDIA Driver (535+) ve NVIDIA Container Toolkit.

---

## 2. Hızlı Başlangıç (Quick Start)

### Adım 1: Depoyu Klonlayın ve Yetkileri Verin
```bash
git clone https://github.com/alpertungax1/flop-mining.git /opt/flop-miner
cd /opt/flop-miner
chmod +x scripts/*.sh
```

### Adım 2: Dizin ve Gizli Anahtarları Oluşturun
```bash
sudo ./scripts/setup.sh
```
*Bu betik `/opt/flop-miner/signer` (0600) ve `/opt/flop-miner/session-keys/enclave.seed` (0600) anahtarlarını otomatik oluşturur.*

### Adım 3: CLI Keystore İçe Aktarımı
```bash
export FLOP_CLI="ghcr.io/flop-labs/flop-core/cli:stable"
read -r -s -p 'Keystore Şifresi Belirleyin: ' FLOP_KEY_PASSWORD && export FLOP_KEY_PASSWORD && echo

MINER_SECRET="$(sudo cat /opt/flop-miner/signer)" docker run --rm --network host \
  -e MINER_SECRET -e FLOP_KEY_PASSWORD -v /opt/flop-miner:/work "$FLOP_CLI" \
  keys import --type sr25519 --secret-env MINER_SECRET --out /work/miner.json \
  --password-env FLOP_KEY_PASSWORD
```

### Adım 4: Devnet Ücretsiz Stake ve Otomatik Kayıt
```bash
sudo env SPONSOR_URL=https://faucet.flop.network FLOP_RPC=wss://rpc.devnet.flop.network ./scripts/sponsor.sh
```

### Adım 5: Model Checkpoint İndirme
```bash
# releases.json'dan model hash'inizi girin (Örn: Qwen2.5-0.5B-Instruct):
MODEL_HASH="0xREPLACE_WITH_REGISTERED_MODEL_HASH"

docker run --rm --network host -v /opt/flop-miner:/work "$FLOP_CLI" \
  --network devnet --rpc wss://rpc.devnet.flop.network model fetch "$MODEL_HASH" \
  --precision BF16 --output-dir /work/models/qwen2.5-0.5b-instruct --json
```

### Adım 6: Yapılandırma Dosyası (`miner-01.env`)
```bash
cp miner.env.example miner-01.env
chmod 600 miner-01.env
nano miner-01.env
```
*Gerekli alanları doldurun:*
- `SESSION_PUBLIC_HOST`: DNS adınız (örn: `miner.alanadiniz.com`).
- `INFERENCE_API_KEY`: `openssl rand -hex 32` çıktısı.
- `SESSION_AUTH_TOKEN`: `openssl rand -hex 32` çıktısı.
- `MODEL_HASH`: İndirdiğiniz modelin hash değeri.

Ardından decode politikasını zincirle bağlayın:
```bash
sudo ./scripts/decode-policy.sh miner-01.env
```

### Adım 7: Servisleri Başlatma ve İzleme
```bash
# 1. Backend GPU servisini başlatın
docker compose --env-file miner-01.env -f docker-compose.backend.yml up -d
docker compose logs -f backend

# 2. Worker ve TLS servisini başlatın
docker compose --env-file miner-01.env -f docker-compose.miner.yml -f docker-compose.tls.yml up -d
docker compose ps
```

### Adım 8: Sağlık ve Kalibrasyon Doğrulaması
```bash
./scripts/check-health.sh miner-01.env
```
*Mailbox üzerinden gelen 64–512 adet Ghost görevi tamamlandıktan sonra madenciniz zincirde `is_ready: true` durumuna geçer ve hesaplama kotası tahsis edilir.*

---

# 🇬🇧 ENGLISH SETUP & OPERATIONS GUIDE

## 1. Hardware & System Requirements

* **OS**: Ubuntu 22.04 or 24.04 LTS (x86_64).
* **GPU**: NVIDIA GPU with at least 16 GB - 24 GB+ VRAM (Devnet reference drill verified on **NVIDIA A40**; RTX 3090/4090, A5000, A6000, A100, H100 supported).
* **Storage**: Minimum 60–100 GB fast NVMe/SSD space.
* **Networking**: Static IP or DNS record (e.g. `miner.yourdomain.com`) with inbound ports 80 and 443 open.
* **Software**: Docker Engine 24+, Docker Compose v2, NVIDIA Driver (535+) and NVIDIA Container Toolkit.

---

## 2. Step-by-Step Walkthrough

### Step 1: Clone Repository & Set Permissions
```bash
git clone https://github.com/alpertungax1/flop-mining.git /opt/flop-miner
cd /opt/flop-miner
chmod +x scripts/*.sh
```

### Step 2: Initialize Directories & Key Seeds
```bash
sudo ./scripts/setup.sh
```
*Generates root-owned, mode-0600 files for `/opt/flop-miner/signer` and `/opt/flop-miner/session-keys/enclave.seed`.*

### Step 3: Import into Encrypted CLI Keystore
```bash
export FLOP_CLI="ghcr.io/flop-labs/flop-core/cli:stable"
read -r -s -p 'Enter Keystore Password: ' FLOP_KEY_PASSWORD && export FLOP_KEY_PASSWORD && echo

MINER_SECRET="$(sudo cat /opt/flop-miner/signer)" docker run --rm --network host \
  -e MINER_SECRET -e FLOP_KEY_PASSWORD -v /opt/flop-miner:/work "$FLOP_CLI" \
  keys import --type sr25519 --secret-env MINER_SECRET --out /work/miner.json \
  --password-env FLOP_KEY_PASSWORD
```

### Step 4: Request Devnet Stake Sponsorship
```bash
sudo env SPONSOR_URL=https://faucet.flop.network FLOP_RPC=wss://rpc.devnet.flop.network ./scripts/sponsor.sh
```

### Step 5: Download & Verify Model Checkpoint
```bash
MODEL_HASH="0xREPLACE_WITH_REGISTERED_MODEL_HASH"

docker run --rm --network host -v /opt/flop-miner:/work "$FLOP_CLI" \
  --network devnet --rpc wss://rpc.devnet.flop.network model fetch "$MODEL_HASH" \
  --precision BF16 --output-dir /work/models/qwen2.5-0.5b-instruct --json
```

### Step 6: Environment File Setup (`miner-01.env`)
```bash
cp miner.env.example miner-01.env
chmod 600 miner-01.env
nano miner-01.env
```
Populate `SESSION_PUBLIC_HOST`, `INFERENCE_API_KEY`, `SESSION_AUTH_TOKEN`, and `MODEL_HASH`. Then resolve allowlisted decode policy:
```bash
sudo ./scripts/decode-policy.sh miner-01.env
```

### Step 7: Launch Containers
```bash
# Start backend first
docker compose --env-file miner-01.env -f docker-compose.backend.yml up -d
docker compose logs -f backend

# Start worker and TLS reverse proxy
docker compose --env-file miner-01.env -f docker-compose.miner.yml -f docker-compose.tls.yml up -d
docker compose ps
```

### Step 8: Diagnostics & Calibration
```bash
./scripts/check-health.sh miner-01.env
```

---

## 🛠️ Troubleshooting Matrix / Sorun Giderme

| Belirti / Symptom | Kök Neden / Root Cause | Çözüm / Remedy |
| :--- | :--- | :--- |
| **GPU Missing in Docker** | Container toolkit not configured | Run `nvidia-ctk runtime configure --runtime=docker && sudo systemctl restart docker`. |
| **Backend Crash Loop** | VRAM exhaustion or hash mismatch | Verify `MODEL_HASH` matches downloaded files; ensure GPU has ≥16GB VRAM. |
| **Sponsorship 429** | Devnet uncalibrated cap reached (100) | Wait a few minutes for an existing miner to calibrate, then rerun `sponsor.sh`. |
| **Sponsorship 403** | Key marked as validator or invalid | Generate a brand-new dedicated `sr25519` keypair. |
| **Calibration Timeout / Slashing** | Worker restarted or ports closed | Keep worker continuously running; ensure ports 80/443 resolve to `caddy`. |
| **Missing TOPLOC** | Incorrect model precision | Ensure both `MODEL_PRECISION=BF16` and `TOPLOC_PRECISION=bf16` are set. |

---

## License
MIT License. Created for the FLOP Network Community.
