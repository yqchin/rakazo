#!/bin/bash
# Runs ON the GPU instance (Ubuntu 24.04, RTX 5090). Installs ComfyUI and the smallest LTX-2.5 file set
# that fits a 32 GB card, then runs ComfyUI as a service on 127.0.0.1:8188 (never exposed publicly).
# Expects the Hugging Face read token on stdin (see connect-gpu.sh). Log: /root/ltx-setup.log
set -euo pipefail
read -r HF_TOKEN
export HF_TOKEN DEBIAN_FRONTEND=noninteractive
exec > >(tee -a /root/ltx-setup.log) 2>&1
echo "== $(date) starting"

nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv || { echo "No NVIDIA driver found"; exit 1; }

apt-get -o DPkg::Lock::Timeout=600 update -y
apt-get -o DPkg::Lock::Timeout=600 install -y git python3-venv python3-pip ffmpeg

cd /root
[ -d ComfyUI ] || git clone --depth 1 https://github.com/comfyanonymous/ComfyUI.git
cd ComfyUI
[ -d venv ] || python3 -m venv venv
. venv/bin/activate
pip install -q --upgrade pip
# CUDA 12.8 builds support the RTX 5090 (Blackwell).
pip install -q torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu128
pip install -q -r requirements.txt
pip install -q -U "huggingface_hub[hf_xet]"

# Smallest working set for ComfyUI's LTX-2.5 templates (~44.5 GB): INT8 model, INT8 text encoders,
# video/audio decoders and the x2 spatial upscaler.
# The repo's folders already match ComfyUI's models/ folders.
hf download Lightricks/LTX-2.5 \
  diffusion_models/ltx-2.5-22b-distilled-transformer-comfy-int8-convrot.safetensors \
  text_encoders/gemma4-12b-with-proj-ltx-2.5-comfy-int8-convrot.safetensors \
  vae/ltx-2.5-video-vae-bf16.safetensors \
  vae/ltx-2.5-audio-vae-bf16.safetensors \
  latent_upscale_models/ltx-2.5-latent-spatial-upscaler-x2-bf16-1.0.safetensors \
  --local-dir /root/ComfyUI/models
# ComfyUI's LTX-2.5 templates also use this small text encoder (public, not gated).
hf download Comfy-Org/gemma-4 text_encoders/gemma4_e2b_it_int8_convrot.safetensors --local-dir /root/ComfyUI/models
unset HF_TOKEN

cat > /etc/systemd/system/comfyui.service <<UNIT
[Unit]
Description=ComfyUI
After=network-online.target

[Service]
WorkingDirectory=/root/ComfyUI
# Hostinger GPU instances are containers: no swap, and pinned host memory does not work through
# their GPU proxy. Load models one at a time and keep VRAM headroom so LTX-2.5 fits in 32 GB.
ExecStart=/root/ComfyUI/venv/bin/python main.py --listen 127.0.0.1 --port 8188 --disable-dynamic-vram --reserve-vram 1.5 --disable-pinned-memory
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
systemctl enable --now comfyui
for i in $(seq 1 60); do curl -fs http://127.0.0.1:8188/system_stats >/dev/null && break; sleep 5; done
curl -fs http://127.0.0.1:8188/system_stats | head -c 400; echo
echo "== $(date) DONE: ComfyUI with LTX-2.5 is running on 127.0.0.1:8188"
