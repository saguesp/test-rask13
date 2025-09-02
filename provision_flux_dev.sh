#!/bin/bash

source /venv/main/bin/activate
COMFYUI_DIR=${WORKSPACE}/ComfyUI

# --- OPTIMIZACIÓN ---
# Añadimos aria2, una herramienta de descarga mucho más rápida que wget.
APT_PACKAGES=(
    "aria2"
    #"package-2"
)

PIP_PACKAGES=(
    #"package-1"
    #"package-2"
)

NODES=(
    #"https://github.com/ltdrdata/ComfyUI-Manager"
    #"https://github.com/cubiq/ComfyUI_essentials"
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
    provisioning_get_nodes
    provisioning_get_pip_packages
    workflows_dir="${COMFYUI_DIR}/user/default/workflows"
    mkdir -p "${workflows_dir}"
    provisioning_get_files \
        "${workflows_dir}" \
        "${WORKFLOWS[@]}"
    # Get licensed models if HF_TOKEN set & valid
    if provisioning_has_valid_hf_token; then
        UNET_MODELS+=("https://huggingface.co/black-forest-labs/FLUX.1-dev/resolve/main/flux1-dev.safetensors")
        VAE_MODELS+=("https://huggingface.co/black-forest-labs/FLUX.1-dev/resolve/main/ae.safetensors")
    else
        UNET_MODELS+=("https://huggingface.co/black-forest-labs/FLUX.1-schnell/resolve/main/flux1-schnell.safetensors")
        VAE_MODELS+=("https://huggingface.co/black-forest-labs/FLUX.1-schnell/resolve/main/ae.safetensors")
        sed -i 's/flux1-dev\.safetensors/flux1-schnell.safetensors/g' "${workflows_dir}/flux_dev_example.json"
    fi
    provisioning_get_files \
        "${COMFYUI_DIR}/models/unet" \
        "${UNET_MODELS[@]}"
    provisioning_get_files \
        "${COMFYUI_DIR}/models/vae" \
        "${VAE_MODELS[@]}"
    provisioning_get_files \
        "${COMFYUI_DIR}/models/clip" \
        "${CLIP_MODELS[@]}"
    provisioning_print_end
}

function provisioning_get_apt_packages() {
    if [[ ${#APT_PACKAGES[@]} -gt 0 ]]; then
        printf "Installing APT packages: %s\n" "${APT_PACKAGES[*]}"
        # El comando 'sudo apt-get install -y' ya está en la variable $APT_INSTALL del entorno base
        sudo $APT_INSTALL ${APT_PACKAGES[@]}
    fi
}

function provisioning_get_pip_packages() {
    if [[ ${#PIP_PACKAGES[@]} -gt 0 ]]; then
        pip install --no-cache-dir ${PIP_PACKAGES[@]}
    fi
}

function provisioning_get_nodes() {
    for repo in "${NODES[@]}"; do
        dir="${repo##*/}"
        path="${COMFYUI_DIR}/custom_nodes/${dir}"
        requirements="${path}/requirements.txt"
        if [[ -d $path ]]; then
            if [[ ${AUTO_UPDATE,,} != "false" ]]; then
                printf "Updating node: %s...\n" "${repo}"
                ( cd "$path" && git pull )
                if [[ -e $requirements ]]; then
                   pip install --no-cache-dir -r "$requirements"
                fi
            fi
        else
            printf "Downloading node: %s...\n" "${repo}"
            git clone "${repo}" "${path}" --recursive
            if [[ -e $requirements ]]; then
                pip install --no-cache-dir -r "${requirements}"
            fi
        fi
    done
}

# --- OPTIMIZACIÓN ---
# Esta función ahora descarga todos los archivos en paralelo.
function provisioning_get_files() {
    if [[ -z $2 ]]; then return 1; fi
    
    dir="$1"
    mkdir -p "$dir"
    shift
    arr=("$@")

    if [[ ${#arr[@]} -eq 0 ]]; then return 0; fi

    printf "Downloading %s file(s) to %s in parallel...\n" "${#arr[@]}" "$dir"
    
    for url in "${arr[@]}"; do
        # Lanzamos cada descarga en segundo plano con '&'
        provisioning_download "${url}" "${dir}" &
    done
    
    # 'wait' espera a que todos los procesos en segundo plano (las descargas) terminen
    wait
    printf "All files for %s downloaded.\n\n" "$dir"
}

function provisioning_print_header() {
    printf "\n##############################################\n#                                            #\n#          Provisioning container            #\n#                                            #\n#         This will take some time           #\n#                                            #\n# Your container will be ready on completion #\n#                                            #\n##############################################\n\n"
}

function provisioning_print_end() {
    printf "\nProvisioning complete:  Application will start now\n\n"
}

function provisioning_has_valid_hf_token() {
    [[ -n "$HF_TOKEN" ]] || return 1
    # Usamos curl para verificar el token
    if curl -s -o /dev/null -w "%{http_code}" -H "Authorization: Bearer $HF_TOKEN" "https://huggingface.co/api/whoami-v2" | grep -q "200"; then
        return 0
    else
        return 1
    fi
}

# --- OPTIMIZACIÓN ---
# Reemplazamos wget con aria2c para descargas mucho más rápidas y robustas.
# Utiliza múltiples conexiones por archivo para saturar el ancho de banda.
function provisioning_download() {
    url="$1"
    dir="$2"
    
    # Construimos las cabeceras para tokens de autenticación si existen
    headers=()
    if [[ -n $HF_TOKEN && $url =~ ^https://([a-zA-Z0-9_-]+\.)?huggingface\.co ]]; then
        headers+=("--header=Authorization: Bearer $HF_TOKEN")
    elif [[ -n $CIVITAI_TOKEN && $url =~ ^https://([a-zA-Z0-9_-]+\.)?civitai\.com ]]; then
        headers+=("--header=Authorization: Bearer $CIVITAI_TOKEN")
    fi
    
    printf "Queueing for download: %s\n" "${url##*/}"
    
    # Parámetros de aria2c:
    # -c, --continue=true: Reanuda descargas interrumpidas.
    # -x 16: Usa hasta 16 conexiones por servidor para cada descarga.
    # -s 16: Divide la descarga en 16 partes.
    # -k 1M: Tamaño mínimo de cada parte (1 Megabyte).
    # --console-log-level=warn: Muestra solo errores o advertencias para no saturar el log.
    # --summary-interval=0: No muestra resumenes periodicos, solo al final.
    # -d "$dir": Directorio de destino.
    # --content-disposition: Usa el nombre de archivo sugerido por el servidor.
    aria2c --console-log-level=warn --summary-interval=0 -c -x 16 -s 16 -k 1M --content-disposition "${headers[@]}" -d "$dir" "$url"
}


# Allow user to disable provisioning if they started with a script they didn't want
if [[ ! -f /.noprovisioning ]]; then
    provisioning_start
fi
