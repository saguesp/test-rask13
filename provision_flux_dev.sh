#!/bin/bash
# --- MODO DEBUG: Muestra cada comando que se ejecuta en los logs ---
set -x

source /venv/main/bin/activate
COMFYUI_DIR=${WORKSPACE}/ComfyUI

# --- PAQUETES DEL SISTEMA (APT) ---
APT_PACKAGES=(
    "jq"
    "aria2"
)

# --- PAQUETES DE PYTHON (PIP) ---
PIP_PACKAGES=()

# --- NODOS PERSONALIZADOS ---
NODES=(
    "https://github.com/ltdrdata/ComfyUI-Manager"
    "https://github.com/cubiq/ComfyUI_essentials"
    "https://github.com/WASasquatch/was-node-suite-comfyui"
    "https://github.com/pythongosssss/ComfyUI-Custom-Scripts"
)

# --- WORKFLOWS ---
WORKFLOWS=(
    "https://gist.githubusercontent.com/rgd87/566887570415a7f960920d0f509e5399/raw/flux_dev_lora_example.json"
)

# --- LISTAS DE MODELOS (se rellenarán automáticamente) ---
CHECKPOINT_MODELS=()
CLIP_MODELS=(
    "https://huggingface.co/comfyanonymous/flux_text_encoders/resolve/main/clip_l.safetensors"
    "https://huggingface.co/comfyanonymous/flux_text_encoders/resolve/main/t5xxl_fp16.safetensors"
)
VAE_MODELS=()
LORA_MODELS=(
    "https://civitai.com/api/download/models/122359" # Detail Tweaker XL
    "https://civitai.com/api/download/models/262131" # Perfect Light and Shadow
    "https://civitai.com/api/download/models/132957" # XL More Art
)


### NO EDITAR DEBAJO DE ESTA LÍNEA ###

function provisioning_start() {
    provisioning_print_header
    # --- PASO 1: Instalar paquetes del sistema PRIMERO ---
    provisioning_get_apt_packages

    printf "Actualizando ComfyUI y dependencias...\n"
    cd ${COMFYUI_DIR} && git pull && pip install -r requirements.txt
    cd ${WORKSPACE}

    provisioning_get_nodes
    provisioning_get_pip_packages

    workflows_dir="${COMFYUI_DIR}/user/default/workflows"
    mkdir -p "${workflows_dir}"
    provisioning_get_files "${workflows_dir}" "${WORKFLOWS[@]}"

    local MODEL_FILENAME=""
    if provisioning_has_valid_hf_token; then
        echo "Token de Hugging Face detectado y válido. Descargando modelo FLUX.1-dev-fp8..."
        MODEL_FILENAME="flux1-dev-fp8.safetensors"
        CHECKPOINT_MODELS+=("https://huggingface.co/black-forest-labs/FLUX.1-dev/resolve/main/${MODEL_FILENAME}")
        VAE_MODELS+=("https://huggingface.co/black-forest-labs/FLUX.1-dev/resolve/main/ae.safetensors")
    else
        echo "No se encontró un token de HF válido. Descargando modelo público FLUX.1-schnell..."
        MODEL_FILENAME="flux1-schnell.safetensors"
        CHECKPOINT_MODELS+=("https://huggingface.co/black-forest-labs/FLUX.1-schnell/resolve/main/${MODEL_FILENAME}")
        VAE_MODELS+=("https://huggingface.co/black-forest-labs/FLUX.1-schnell/resolve/main/ae.safetensors")
    fi

    # Modificar el workflow JSON
    local workflow_file="${workflows_dir}/flux_dev_lora_example.json"
    if [ -f "$workflow_file" ]; then
        echo "Modificando workflow JSON con el modelo: ${MODEL_FILENAME}"
        jq --arg model_name "$MODEL_FILENAME" '(.nodes[] | select(.type == "CheckpointLoaderSimple").widgets_values) |= [ $model_name ]' "$workflow_file" > "${workflow_file}.tmp" && mv "${workflow_file}.tmp" "$workflow_file"
    fi

    # Iniciar todas las descargas
    provisioning_get_files "${COMFYUI_DIR}/models/checkpoints" "${CHECKPOINT_MODELS[@]}"
    provisioning_get_files "${COMFYUI_DIR}/models/vae" "${VAE_MODELS[@]}"
    provisioning_get_files "${COMFYUI_DIR}/models/clip" "${CLIP_MODELS[@]}"
    provisioning_get_files "${COMFYUI_DIR}/models/loras" "${LORA_MODELS[@]}"

    provisioning_print_end
    set +x
}

# --- FUNCIÓN PARA INSTALAR PAQUETES APT ---
function provisioning_get_apt_packages() {
    if [[ ${#APT_PACKAGES[@]} -gt 0 ]]; then
        echo "Instalando paquetes APT: ${APT_PACKAGES[*]}"
        sudo apt-get update
        sudo apt-get install -y ${APT_PACKAGES[@]}
    fi
}

function provisioning_get_pip_packages() { if [[ ${#PIP_PACKAGES[@]} -gt 0 ]]; then pip install --no-cache-dir ${PIP_PACKAGES[@]}; fi; }
function provisioning_get_nodes() { for repo in "${NODES[@]}"; do dir="${repo##*/}"; path="${COMFYUI_DIR}/custom_nodes/${dir}"; requirements="${path}/requirements.txt"; if [[ -d $path ]]; then if [[ ${AUTO_UPDATE,,} != "false" ]]; then printf "Updating node: %s...\n" "${repo}"; ( cd "$path" && git pull ); if [[ -e $requirements ]]; then pip install --no-cache-dir -r "$requirements"; fi; fi; else printf "Downloading node: %s...\n" "${repo}"; git clone "${repo}" "${path}" --recursive; if [[ -e $requirements ]]; then pip install --no-cache-dir -r "$requirements"; fi; fi; done; }
function provisioning_get_files() { if [[ -z $2 ]]; then return 1; fi; dir="$1"; mkdir -p "$dir"; shift; arr=("$@"); printf "Downloading %s model(s) to %s...\n" "${#arr[@]}" "$dir"; for url in "${arr[@]}"; do printf "Downloading: %s\n" "${url}"; provisioning_download "${url}" "${dir}"; printf "\n"; done; }

# --- FUNCIÓN DE DESCARGA 100% CORREGIDA ---
function provisioning_download() {
    local auth_header=""
    if [[ -n $HF_TOKEN && $1 =~ ^https://([a-zA-Z0--9]+\.)?huggingface\.co(/|$|\?) ]]; then
        auth_header="Authorization: Bearer $HF_TOKEN"
    elif [[ -n $CIVITAI_TOKEN && $1 =~ ^https://([a-zA-Z0-9_-]+\.)?civitai\.com(/|$|\?) ]]; then
        auth_header="Authorization: Bearer $CIVITAI_TOKEN"
    fi

    if command -v aria2c &> /dev/null; then
        echo "Descargando con aria2c (rápido)..."
        if [[ -n "$auth_header" ]]; then
            # --- ESTA ES LA LÍNEA CLAVE, AHORA ESTÁ PERFECTA ---
            aria2c --console-log-level=error -c -x 16 -s 16 -k 1M --header="$auth_header" --dir="$2" --out="${1##*/}" "$1"
        else
            aria2c --console-log-level=error -c -x 16 -s 16 -k 1M --dir="$2" --out="${1##*/}" "$1"
        fi
    else
        echo "aria2c no encontrado. Usando wget (lento)..."
        if [[ -n "$auth_header" ]];then
            wget --header="$auth_header" -qnc --content-disposition --show-progress -e dotbytes="4M" -P "$2" "$1"
        else
            wget -qnc --content-disposition --show-progress -e dotbytes="4M" -P "$2" "$1"
        fi
    fi
}

function provisioning_print_header() { printf "\n##############################################\n#                                            #\n#          Provisioning container            #\n#                                            #\n#         This will take some time           #\n#                                            #\n# Your container will be ready on completion #\n#                                            #\n##############################################\n\n"; }
function provisioning_print_end() { printf "\nProvisioning complete:  Application will start now\n\n"; }
function provisioning_has_valid_hf_token() { [[ -n "$HF_TOKEN" ]] || return 1; url="https://huggingface.co/api/whoami-v2"; response=$(curl -o /dev/null -s -w "%{http_code}" -X GET "$url" -H "Authorization: Bearer $HF_TOKEN" -H "Content-Type: application/json"); if [ "$response" -eq 200 ]; then return 0; else return 1; fi; }

if [[ ! -f /.noprovisioning ]]; then
    provisioning_start
fi
