#!/bin/bash
# Modo estricto + trazas
set -Eeuo pipefail
IFS=$'\n\t'
set -x

source /venv/main/bin/activate || true

: "${WORKSPACE:=${HOME}}"
COMFYUI_DIR="${WORKSPACE}/ComfyUI"

# --- Paquetes (puedes añadir los tuyos) ---
APT_PACKAGES=(
  "git" "wget" "jq" "ca-certificates" "curl"
)

PIP_PACKAGES=(
  # "package-1"
  # "package-2"
)

NODES=(
  # "https://github.com/ltdrdata/ComfyUI-Manager"
  # "https://github.com/cubiq/ComfyUI_essentials"
)

WORKFLOWS=(
  "https://gist.githubusercontent.com/robballantyne/f8cb692bdcd89c96c0bd1ec0c969d905/raw/2d969f732d7873f0e1ee23b2625b50f201c722a5/flux_dev_example.json"
)

CLIP_MODELS=(
  "https://huggingface.co/comfyanonymous/flux_text_encoders/resolve/main/clip_l.safetensors"
  "https://huggingface.co/comfyanonymous/flux_text_encoders/resolve/main/t5xxl_fp16.safetensors"
)

UNET_MODELS=(
)

VAE_MODELS=(
)

### DO NOT EDIT BELOW HERE UNLESS YOU KNOW WHAT YOU ARE DOING ###

function provisioning_start() {
    provisioning_print_header
    provisioning_get_apt_packages

    # Clonar/actualizar ComfyUI si es necesario (la base lo asume existente)
    if [[ -d "${COMFYUI_DIR}/.git" ]]; then
        printf "Updating ComfyUI...\n"
        ( cd "${COMFYUI_DIR}" && git pull --rebase )
    else
        printf "Cloning ComfyUI...\n"
        git clone --depth 1 https://github.com/comfyanonymous/ComfyUI.git "${COMFYUI_DIR}"
    fi

    provisioning_get_nodes
    provisioning_get_pip_packages

    local workflows_dir="${COMFYUI_DIR}/user/default/workflows"
    mkdir -p "${workflows_dir}"
    provisioning_get_files "${workflows_dir}" "${WORKFLOWS[@]}"

    # Get licensed models if HF_TOKEN set & valid
    if provisioning_has_valid_hf_token; then
        UNET_MODELS+=("https://huggingface.co/black-forest-labs/FLUX.1-dev/resolve/main/flux1-dev.safetensors")
        VAE_MODELS+=("https://huggingface.co/black-forest-labs/FLUX.1-dev/resolve/main/ae.safetensors")
    else
        UNET_MODELS+=("https://huggingface.co/black-forest-labs/FLUX.1-schnell/resolve/main/flux1-schnell.safetensors")
        VAE_MODELS+=("https://huggingface.co/black-forest-labs/FLUX.1-schnell/resolve/main/ae.safetensors")
        # Solo sed si el workflow existe
        if [[ -f "${workflows_dir}/flux_dev_example.json" ]]; then
          sed -i 's/flux1-dev\.safetensors/flux1-schnell.safetensors/g' "${workflows_dir}/flux_dev_example.json"
        fi
    fi

    # Carpetas de modelos (y symlink por compatibilidad con "checkpoints")
    mkdir -p "${COMFYUI_DIR}/models/unet" "${COMFYUI_DIR}/models/vae" "${COMFYUI_DIR}/models/clip"
    if [[ ! -e "${COMFYUI_DIR}/models/checkpoints" ]]; then
      ln -s "${COMFYUI_DIR}/models/unet" "${COMFYUI_DIR}/models/checkpoints" || true
    fi

    provisioning_get_files "${COMFYUI_DIR}/models/unet" "${UNET_MODELS[@]}"
    provisioning_get_files "${COMFYUI_DIR}/models/vae"  "${VAE_MODELS[@]}"
    provisioning_get_files "${COMFYUI_DIR}/models/clip" "${CLIP_MODELS[@]}"

    provisioning_print_end
}

function provisioning_get_apt_packages() {
    if [[ ${#APT_PACKAGES[@]} -gt 0 ]]; then
        sudo apt-get update -y
        sudo apt-get install -y --no-install-recommends "${APT_PACKAGES[@]}"
        sudo apt-get clean
    fi
}

function provisioning_get_pip_packages() {
    if [[ ${#PIP_PACKAGES[@]} -gt 0 ]]; then
        pip install --no-cache-dir "${PIP_PACKAGES[@]}"
    fi
}

function provisioning_get_nodes() {
    for repo in "${NODES[@]}"; do
        dir="${repo##*/}"
        path="${COMFYUI_DIR}/custom_nodes/${dir}"   # <-- slash FIX
        requirements="${path}/requirements.txt"
        if [[ -d $path ]]; then
            if [[ ${AUTO_UPDATE,,} != "false" ]]; then
                printf "Updating node: %s...\n" "${repo}"
                ( cd "$path" && git pull )
                if [[ -e $requirements ]]; then
                   pip install --no-cache-dir -r "$requirements" || true
                fi
            fi
        else
            printf "Downloading node: %s...\n" "${repo}"
            git clone "${repo}" "${path}" --recursive
            if [[ -e $requirements ]]; then
                pip install --no-cache-dir -r "${requirements}" || true
            fi
        fi
    done
}

function provisioning_get_files() {
    # $1 dest_dir; resto: urls
    if [[ $# -lt 2 ]]; then return 0; fi
    local dir="$1"; shift
    mkdir -p "$dir"
    local arr=("$@")
    printf "Downloading %s file(s) to %s...\n" "${#arr[@]}" "$dir"
    for url in "${arr[@]}"; do
        printf "Downloading: %s\n" "${url}"
        provisioning_download "${url}" "${dir}"
        printf "\n"
    done
}

function provisioning_print_header() {
    printf "\n##############################################\n#                                            #\n#          Provisioning container            #\n#                                            #\n#                Please wait                 #\n#                                            #\n# Your container will be ready on completion #\n#                                            #\n##############################################\n\n"
}

function provisioning_print_end() {
    printf "\nProvisioning complete:  Application will start now\n\n"
}

function provisioning_has_valid_hf_token() {
    [[ -n "${HF_TOKEN:-}" ]] || return 1
    local url="https://huggingface.co/api/whoami-v2"
    local response
    response=$(curl -o /dev/null -s -w "%{http_code}" -X GET "$url" \
        -H "Authorization: Bearer $HF_TOKEN" \
        -H "Content-Type: application/json")
    [[ "$response" -eq 200 ]]
}

function provisioning_has_valid_civitai_token() {
    [[ -n "${CIVITAI_TOKEN:-}" ]] || return 1
    local url="https://civitai.com/api/v1/models?hidden=1&limit=1"
    local response
    response=$(curl -o /dev/null -s -w "%{http_code}" -X GET "$url" \
        -H "Authorization: Bearer $CIVITAI_TOKEN" \
        -H "Content-Type: application/json")
    [[ "$response" -eq 200 ]]
}

# Download from $1 URL to $2 dir (keeps server filename)
function provisioning_download() {
    local url="$1"; local destdir="$2"
    local auth_token=""
    if [[ -n "${HF_TOKEN:-}" && $url =~ ^https://([a-zA-Z0-9_-]+\.)?huggingface\.co(/|$|\?) ]]; then
        auth_token="$HF_TOKEN"
    elif [[ -n "${CIVITAI_TOKEN:-}" && $url =~ ^https://([a-zA-Z0-9_-]+\.)?civitai\.com(/|$|\?) ]]; then
        auth_token="$CIVITAI_TOKEN"
    fi
    if [[ -n $auth_token ]]; then
        wget --header="Authorization: Bearer $auth_token" -qnc --content-disposition --show-progress -e dotbytes="${3:-4M}" -P "$destdir" "$url"
    else
        wget -qnc --content-disposition --show-progress -e dotbytes="${3:-4M}" -P "$destdir" "$url"
    fi
}

# Allow user to disable provisioning if they started with a script they didn't want
if [[ ! -f /.noprovisioning ]]; then
    provisioning_start
fi
