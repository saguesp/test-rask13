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
    [[ -f $req ]] && pip install --no-cache-dir -r "$req" || true
  done
}

provisioning_has_valid_hf_token(){
  [[ -n "${HF_TOKEN:-}" ]] || return 1
  code=$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: Bearer $HF_TOKEN" https://huggingface.co/api/whoami-v2)
  [[ "$code" -eq 200 ]]
}

provisioning_download(){
  local url="$1" destdir="$2" token=""
  if [[ -n "${HF_TOKEN:-}" && $url =~ huggingface\.co ]]; then token="$HF_TOKEN"; fi
  if [[ -n "${CIVITAI_TOKEN:-}" && $url =~ civitai\.com ]]; then token="$CIVITAI_TOKEN"; fi
  if [[ -n $token ]]; then
    wget --header="Authorization: Bearer $token" -qnc --content-disposition -P "$destdir" "$url"
  else
    wget -qnc --content-disposition -P "$destdir" "$url"
  fi
}

provisioning_get_files(){
  [[ $# -ge 2 ]] || return 0
  local dir="$1"; shift; mkdir -p "$dir"
  for url in "$@"; do provisioning_download "$url" "$dir"; done
}

provisioning_update_comfyui(){
  if [[ -d "${COMFYUI_DIR}/.git" ]]; then
    echo "Updating ComfyUI safely..."
    ( cd "${COMFYUI_DIR}"
      git fetch --all --tags
      if [[ "$(git rev-parse --abbrev-ref HEAD)" == "HEAD" ]]; then
        git checkout -B master origin/master || git checkout -B main origin/main
      else
        git pull --ff-only
      fi
    )
  else
    echo "Cloning ComfyUI..."
    git clone --depth 1 https://github.com/comfyanonymous/ComfyUI.git "${COMFYUI_DIR}"
  fi
  # Requisitos para corregir la versión de frontend
  [[ -f "${COMFYUI_DIR}/requirements.txt" ]] && \
    /venv/main/bin/python -m pip install -r "${COMFYUI_DIR}/requirements.txt" || true
}

provisioning_start(){
  provisioning_print_header
  provisioning_get_apt_packages
  provisioning_update_comfyui
  provisioning_get_nodes
  provisioning_get_pip_packages

  local wf_dir="${COMFYUI_DIR}/user/default/workflows"
  mkdir -p "${wf_dir}"
  provisioning_get_files "${wf_dir}" "${WORKFLOWS[@]}"

  if provisioning_has_valid_hf_token; then
    CHECKPOINT_MODELS+=("https://huggingface.co/black-forest-labs/FLUX.1-dev/resolve/main/flux1-dev.safetensors")
    VAE_MODELS+=("https://huggingface.co/black-forest-labs/FLUX.1-dev/resolve/main/ae.safetensors")
  else
    CHECKPOINT_MODELS+=("https://huggingface.co/black-forest-labs/FLUX.1-schnell/resolve/main/flux1-schnell.safetensors")
    VAE_MODELS+=("https://huggingface.co/black-forest-labs/FLUX.1-schnell/resolve/main/ae.safetensors")
    [[ -f "${wf_dir}/flux_dev_example.json" ]] && \
      sed -i 's/flux1-dev\.safetensors/flux1-schnell.safetensors/g' "${wf_dir}/flux_dev_example.json" || true
  fi

  # TODO: guardamos TODO en checkpoints como pediste
  mkdir -p "${COMFYUI_DIR}/models/checkpoints"
  provisioning_get_files "${COMFYUI_DIR}/models/checkpoints" "${CHECKPOINT_MODELS[@]}"
  provisioning_get_files "${COMFYUI_DIR}/models/checkpoints" "${VAE_MODELS[@]}"
  provisioning_get_files "${COMFYUI_DIR}/models/checkpoints" "${CLIP_MODELS[@]}"
  provisioning_get_files "${COMFYUI_DIR}/models/checkpoints" "${LORA_MODELS[@]}"

  provisioning_print_end
}

# Llamada única al final
if [[ ! -f /.noprovisioning ]]; then
  provisioning_start
fi
