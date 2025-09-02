#!/bin/bash
set -Eeuo pipefail
IFS=$'\n\t'
set -x

source /venv/main/bin/activate || true
: "${WORKSPACE:=/workspace}"
COMFYUI_DIR="${WORKSPACE}/ComfyUI"

# --- config arrays ---
APT_PACKAGES=(git wget jq ca-certificates curl)
PIP_PACKAGES=()
NODES=()
WORKFLOWS=("https://gist.githubusercontent.com/robballantyne/f8cb692bdcd89c96c0bd1ec0c969d905/raw/2d969f732d7873f0e1ee23b2625b50f201c722a5/flux_dev_example.json")
CLIP_MODELS=(
  "https://huggingface.co/comfyanonymous/flux_text_encoders/resolve/main/clip_l.safetensors"
  "https://huggingface.co/comfyanonymous/flux_text_encoders/resolve/main/t5xxl_fp16.safetensors"
)
CHECKPOINT_MODELS=()
VAE_MODELS=()
LORA_MODELS=()

provisioning_print_header(){ printf "\n### Provisioning container ###\n\n"; }
provisioning_print_end(){ printf "\nProvisioning complete\n\n"; }

provisioning_get_apt_packages(){
  if [[ ${#APT_PACKAGES[@]} -gt 0 ]]; then
    sudo apt-get update -y
    sudo apt-get install -y --no-install-recommends "${APT_PACKAGES[@]}"
    sudo apt-get clean
  fi
}

provisioning_get_pip_packages(){
  if [[ ${#PIP_PACKAGES[@]} -gt 0 ]]; then
    pip install --no-cache-dir "${PIP_PACKAGES[@]}"
  fi
}

provisioning_get_nodes(){
  for repo in "${NODES[@]}"; do
    dir="${repo##*/}"
    path="${COMFYUI_DIR}/custom_nodes/${dir}"
    req="${path}/requirements.txt"
    if [[ -d $path ]]; then
      [[ ${AUTO_UPDATE,,} != "false" ]] && (cd "$path" && git pull) || true
    else
      git clone --recursive "$repo" "$path"
    fi
