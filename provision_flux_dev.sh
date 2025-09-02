#!/bin/bash
# --- MODO DEBUG: Muestra cada comando que se ejecuta en los logs ---
set -x

source /venv/main/bin/activate
COMFYUI_DIR=${WORKSPACE}/ComfyUI

# --- CAMBIO: Añadimos jq para editar JSON de forma fiable ---
APT_PACKAGES=(
    "jq"
)

PIP_PACKAGES=(
    #"package-1"
)

NODES=(
    "https://github.com/ltdrdata/ComfyUI-Manager"
    "https://github.com/cubiq/ComfyUI_essentials"
)

WORKFLOWS=(
    "https://gist.githubusercontent.com/robballantyne/f8cb692bdcd89c96c0bd1ec0c969d905/raw/2d969f732d7873f0e1ee23b2625b50f201c722a5/flux_dev_example.json"
)

CHECKPOINT_MODELS=()
CLIP_MODELS=(
    "https://huggingface.co/comfyanonymous/flux_text_encoders/resolve/main/clip_l.safetensors"
    "https://huggingface.co/comfyanonymous/flux_text_encoders/resolve/main/t5xxl_fp16.safetensors"
)
VAE_MODELS=()
LORA_MODELS=()

### DO NOT EDIT BELOW HERE UNLESS YOU KNOW WHAT YOU ARE DOING ###

function provisioning_start() {
    provisioning_print_header
    provisioning_get_apt_packages

    printf "Actualizando ComfyUI y dependencias...\n"
    cd ${COMFYUI_DIR}
    git pull
    pip install -r requirements.txt
    cd ${WORKSPACE}

    provisioning_get_nodes
    provisioning_get_pip_packages

    workflows_dir="${COMFYUI_DIR}/user/default/workflows"
    workflow_file="${workflows_dir}/flux_dev_example.json"
    mkdir -p "${workflows_dir}"
    provisioning_get_files "${workflows_dir}" "${WORKFLOWS[@]}"

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

    # --- CAMBIO IMPORTANTE: Usamos jq para insertar el nombre del modelo en el workflow ---
    # Esto busca el nodo CheckpointLoaderSimple (en tu caso tiene el id 30) y establece su ckpt_name
    # Es mucho más robusto que sed, ya que no depende del valor anterior (funciona incluso si es null)
    if [ -f "$workflow_file" ]; then
        echo "Modificando workflow JSON con el modelo: ${MODEL_FILENAME}"
        jq --arg model_name "$MODEL_FILENAME" '(.nodes[] | select(.type == "CheckpointLoaderSimple").widgets_values) |= [ $model_name ]' "$workflow_file" > "${workflow_file}.tmp" && mv "${workflow_file}.tmp" "$workflow_file"
    fi

    provisioning_get_files "${COMFYUI_DIR}/models/checkpoints" "${CHECKPOINT_MODELS[@]}"
    provisioning_get_files "${COMFYUI_DIR}/models/vae" "${VAE_MODELS[@]}"
    provisioning_get_files "${COMFYUI_DIR}/models/clip" "${CLIP_MODELS[@]}"

    loras_dir="${COMFYUI_DIR}/models/loras"
    mkdir -p "${loras_dir}"
    if [[ -n "${LORA_URLS}" ]]; then
        while IFS= read -r line; do [[ -z "$line" ]] && continue; LORA_MODELS+=("$line"); done < <(printf "%s" "$LORA_URLS" | tr ' ' '\n')
    fi
    if [[ -f "${WORKSPACE}/lora_urls.txt" ]]; then
        while IFS= read -r url; do [[ -z "$url" ]] && continue; LORA_MODELS+=("$url"); done < "${WORKSPACE}/lora_urls.txt"
    fi
    provisioning_get_files "${loras_dir}" "${LORA_MODELS[@]}"

    provisioning_print_end
    # --- Apagamos el modo debug al final ---
    set +x
}

# (El resto de las funciones provisioning_* se mantienen igual)
# ... (copia y pega el resto de tu script anterior aquí) ...
function provisioning_get_apt_packages() {
    if [[ ${#APT_PACKAGES[@]} -gt 0 ]]; then
        sudo apt-get update
        sudo apt-get install -y ${APT_PACKAGES[@]}
    fi
}
function provisioning_get_pip_packages() { if [[ -n $PIP_PACKAGES ]]; then pip install --no-cache-dir ${PIP_PACKAGES[@]}; fi; }
function provisioning_get_nodes() { for repo in "${NODES[@]}"; do dir="${repo##*/}"; path="${COMFYUI_DIR}custom_nodes/${dir}"; requirements="${path}/requirements.txt"; if [[ -d $path ]]; then if [[ ${AUTO_UPDATE,,} != "false" ]]; then printf "Updating node: %s...\n" "${repo}"; ( cd "$path" && git pull ); if [[ -e $requirements ]]; then pip install --no-cache-dir -r "$requirements"; fi; fi; else printf "Downloading node: %s...\n" "${repo}"; git clone "${repo}" "${path}" --recursive; if [[ -e $requirements ]]; then pip install --no-cache-dir -r "${requirements}"; fi; fi; done; }
function provisioning_get_files() { if [[ -z $2 ]]; then return 1; fi; dir="$1"; mkdir -p "$dir"; shift; arr=("$@"); printf "Downloading %s model(s) to %s...\n" "${#arr[@]}" "$dir"; for url in "${arr[@]}"; do printf "Downloading: %s\n" "${url}"; provisioning_download "${url}" "${dir}"; printf "\n"; done; }
function provisioning_print_header() { printf "\n##############################################\n#                                            #\n#          Provisioning container            #\n#                                            #\n#         This will take some time           #\n#                                            #\n# Your container will be ready on completion #\n#                                            #\n##############################################\n\n"; }
function provisioning_print_end() { printf "\nProvisioning complete:  Application will start now\n\n"; }
function provisioning_has_valid_hf_token() { [[ -n "$HF_TOKEN" ]] || return 1; url="https://huggingface.co/api/whoami-v2"; response=$(curl -o /dev/null -s -w "%{http_code}" -X GET "$url" -H "Authorization: Bearer $HF_TOKEN" -H "Content-Type: application/json"); if [ "$response" -eq 200 ]; then return 0; else return 1; fi; }
function provisioning_has_valid_civitai_token() { [[ -n "$CIVITAI_TOKEN" ]] || return 1; url="https://civitai.com/api/v1/models?hidden=1&limit=1"; response=$(curl -o /dev/null -s -w "%{http_code}" -X GET "$url" -H "Authorization: Bearer $CIVITAI_TOKEN" -H "Content-Type: application/json"); if [ "$response" -eq 200 ]; then return 0; else return 1; fi; }
function provisioning_download() {
    # Prepara la autenticación si es necesaria
    local auth_header=""
    if [[ -n $HF_TOKEN && $1 =~ ^https://([a-zA-Z0-9_-]+\.)?huggingface\.co(/|$|\?) ]]; then
        auth_header="Authorization: Bearer $HF_TOKEN"
    elif [[ -n $CIVITAI_TOKEN && $1 =~ ^https://([a-zA-Z0-9_-]+\.)?civitai\.com(/|$|\?) ]]; then
        auth_header="Authorization: Bearer $CIVITAI_TOKEN"
    fi

    # Usa aria2c si está disponible (es mucho más rápido), si no, usa wget como respaldo
    if command -v aria2c &> /dev/null; then
        echo "Descargando con aria2c (rápido)..."
        if [[ -n $auth_header ]]; then
            # -x 16: usa hasta 16 conexiones por descarga
            # -s 16: divide el archivo en 16 partes
            # -k 1M: tamaño mínimo de cada parte
            aria2c --console-log-level=error -c -x 16 -s 16 -k 1M --header="$auth_header" --dir="$2" --out="${1##*/}" "$1"
        else
            aria2c --console-log-level=error -c -x 16 -s 16 -k 1M --dir="$2" --out="${1##*/}" "$1"
        fi
    else
        echo "aria2c no encontrado. Usando wget (lento)..."
        if [[ -n $auth_header ]];then
            wget --header="$auth_header" -qnc --content-disposition --show-progress -e dotbytes="${3:-4M}" -P "$2" "$1"
        else
            wget -qnc --content-disposition --show-progress -e dotbytes="${3:-4M}" -P "$2" "$1"
        fi
    fi
}
if [[ ! -f /.noprovisioning ]]; then
    provisioning_start
fi
