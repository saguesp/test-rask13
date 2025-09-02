#!/bin/bash

source /venv/main/bin/activate
COMFYUI_DIR=${WORKSPACE}/ComfyUI

# Packages are installed after nodes so we can fix them...

APT_PACKAGES=(
    # "package-1"
    # "package-2"
)

PIP_PACKAGES=(
    "onnxruntime-gpu"
    "ultralytics"
    "insightface"
)

NODES=(
    "https://github.com/ltdrdata/ComfyUI-Manager"
    "https://github.com/crystian/ComfyUI-Crystools"
    "https://github.com/Gourieff/comfyui-reactor-node"
    "https://github.com/rgthree/comfy-rgthree"
    "https://github.com/ET-YY/ComfyUI-Portrait-Master"
    "https://github.com/jags111/comfyui-plus"
    "https://github.com/nt-s/MX-Nodes"
    "https://github.com/pythongosssss/ComfyUI-Custom-Scripts"
    "https://github.com/cubiq/ComfyUI_essentials"
    "https://github.com/Derfuu/ComfyUI-Impact-Pack"
    "https://github.com/yoloner/ComfyUI-Tara-AI-nodes"
    "https://github.com/florest2/ComfyUI_Florence2"
    "https://github.com/jtydhr88/ComfyUI-Load-And-Resize-Image"
    "https://github.com/BadCafeCode/ComfyUI-Differential-Diffusion"
    "https://github.com/Gourieff/comfy-expression-editor"
    "https://github.com/BadCafeCode/ComfyUI-ProPost-Nodes"
    "https://github.com/Fannovel16/ComfyUI-Preprocessors"
    "https://github.com/Shakker/ComfyUI-Shakker-Labs"
    "https://github.com/gameltb/ComfyUI-Detail-Daemon"
    "https://github.com/blepping/ComfyUI-Inspire-Pack"
    "https://github.com/chrisgoringe/ComfyUI-send-anywhere"
    "https://github.com/mtb-art/ComfyUI-mtb-nodes"
    "https://github.com/kijai/ComfyUI-Unet-Loader-GGUF"
)

# El workflow JSON proporcionado debe ser guardado como un archivo .json y colocado en
# la carpeta ComfyUI/user/default/workflows
WORKFLOWS=(
)

CLIP_MODELS=(
    "https://huggingface.co/comfyanonymous/flux_text_encoders/resolve/main/clip_l.safetensors"
    "https://huggingface.co/comfyanonymous/flux_text_encoders/resolve/main/t5xxl_fp16.safetensors"
)

# Se usará el modelo GGUF (más ligero en VRAM) que está especificado en el workflow.
# El script base se encargará del modelo principal flux1-dev si tienes un token de HF.
GGUF_MODELS=(
    "https://huggingface.co/city96/FLUX.1-dev-gguf/resolve/main/flux1-dev-Q8_0.gguf"
)

CONTROLNET_MODELS=(
    "https://huggingface.co/Shakker-Labs/FLUX.1-dev-ControlNet-Union-Pro/resolve/main/FLUX1-dev-ControlNet-Union-Pro.safetensors"
)

UPSCALE_MODELS=(
    "https://huggingface.co/uwg/upscaler/resolve/main/ESRGAN/4xNMKDSuperscale_4xNMKDSuperscale.pt"
)

CLIP_VISION_MODELS=(
    # Se descargará como model.safetensors, es necesario renombrarlo.
    # El script lo hará automáticamente.
    "https://huggingface.co/google/siglip-so400m-patch14-384/resolve/main/model.safetensors"
)

STYLE_MODELS=(
    "https://huggingface.co/flax-community/flux1-redux-dev/resolve/main/flux1-redux-dev.safetensors"
)

# Modelos para ADetailer (Impact Pack)
SAM_MODELS=(
    "https://huggingface.co/lkeab/sam-vit-b-01ec64/resolve/main/sam_vit_b_01ec64.pth"
)
ULTRALYTICS_MODELS=(
    "https://huggingface.co/Bingsu/adetailer/resolve/main/hand_yolov8s.pt"
    "https://huggingface.co/Bingsu/adetailer/resolve/main/face_yolov8n_v2.pt"
    "https://civitai.com/api/download/models/303534" # Eyeful_v2-Paired.pt
)

# Modelos para ReActor
REACTOR_INSIGHTFACE_MODELS=(
    "https://huggingface.co/datasets/Gourieff/ReActor/resolve/main/models/inswapper_128.onnx"
)
REACTOR_GFPGAN_MODELS=(
    "https://github.com/TencentARC/GFPGAN/releases/download/v1.3.0/GFPGANv1.4.pth"
)
REACTOR_GPEN_MODELS=(
    "https://huggingface.co/datasets/Gourieff/ReActor/resolve/main/models/GPEN-BFR-512.onnx"
)

# Modelos para Preprocessors
DEPTH_ANYTHING_MODELS=(
    "https://huggingface.co/depth-anything/Depth-Anything-VIT-Large/resolve/main/depth_anything_vitl14.pth"
)

# Ficheros LUT para Post-Processing
LUT_MODELS=(
    "https://raw.githubusercontent.com/eieioxx/ComfyUI-ProPost-Nodes/main/luts/Presetpro%20-%20Portra%20800.cube"
)

# Ficheros de fuentes
FONT_FILES=(
    "https://github.com/JotJunior/PHP-Boleto-ZF2/blob/master/public/assets/fonts/comic.ttf?raw=true"
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
    
    # Descargar todos los modelos en sus carpetas correspondientes
    provisioning_get_files "${COMFYUI_DIR}/models/unet" "${UNET_MODELS[@]}"
    provisioning_get_files "${COMFYUI_DIR}/models/unet" "${GGUF_MODELS[@]}"
    provisioning_get_files "${COMFYUI_DIR}/models/vae" "${VAE_MODELS[@]}"
    provisioning_get_files "${COMFYUI_DIR}/models/clip" "${CLIP_MODELS[@]}"
    provisioning_get_files "${COMFYUI_DIR}/models/controlnet" "${CONTROLNET_MODELS[@]}"
    provisioning_get_files "${COMFYUI_DIR}/models/upscale_models" "${UPSCALE_MODELS[@]}"
    provisioning_get_files "${COMFYUI_DIR}/models/style_models" "${STYLE_MODELS[@]}"
    provisioning_get_files "${COMFYUI_DIR}/models/sam" "${SAM_MODELS[@]}"
    provisioning_get_files "${COMFYUI_DIR}/models/ultralytics/bbox" "${ULTRALYTICS_MODELS[@]}"
    provisioning_get_files "${COMFYUI_DIR}/models/insightface" "${REACTOR_INSIGHTFACE_MODELS[@]}"
    provisioning_get_files "${COMFYUI_DIR}/models/gfpgan" "${REACTOR_GFPGAN_MODELS[@]}"
    provisioning_get_files "${COMFYUI_DIR}/models/gpen" "${REACTOR_GPEN_MODELS[@]}"
    provisioning_get_files "${COMFYUI_DIR}/models/depth_anything" "${DEPTH_ANYTHING_MODELS[@]}"
    provisioning_get_files "${COMFYUI_DIR}/models/luts" "${LUT_MODELS[@]}"
    provisioning_get_files "${COMFYUI_DIR}/fonts" "${FONT_FILES[@]}"

    # Descarga y renombra el modelo CLIP Vision
    printf "Descargando modelo CLIP Vision y renombrando...\n"
    provisioning_download "${CLIP_VISION_MODELS[0]}" "${COMFYUI_DIR}/models/clip_vision" "sigclip_vision_patch14_384.safetensors"
    
    provisioning_print_end
}

function provisioning_get_apt_packages() {
    if [[ -n $APT_PACKAGES ]]; then
            sudo $APT_INSTALL ${APT_PACKAGES[@]}
    fi
}

function provisioning_get_pip_packages() {
    if [[ -n $PIP_PACKAGES ]]; then
            pip install --no-cache-dir ${PIP_PACKAGES[@]}
    fi
}

function provisioning_get_nodes() {
    for repo in "${NODES[@]}"; do
        dir="${repo##*/}"
        path="${COMFYUI_DIR}custom_nodes/${dir}"
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

function provisioning_get_files() {
    if [[ -z $2 ]]; then return 1; fi
    
    dir="$1"
    mkdir -p "$dir"
    shift
    arr=("$@")
    printf "Downloading %s model(s) to %s...\n" "${#arr[@]}" "$dir"
    for url in "${arr[@]}"; do
        printf "Downloading: %s\n" "${url}"
        provisioning_download "${url}" "${dir}"
        printf "\n"
    done
}

function provisioning_print_header() {
    printf "\n##############################################\n#                                            #\n#          Provisioning container            #\n#                                            #\n#         This will take some time           #\n#                                            #\n# Your container will be ready on completion #\n#                                            #\n##############################################\n\n"
}

function provisioning_print_end() {
    printf "\nProvisioning complete:  Application will start now\n\n"
}

function provisioning_has_valid_hf_token() {
    [[ -n "$HF_TOKEN" ]] || return 1
    url="https://huggingface.co/api/whoami-v2"

    response=$(curl -o /dev/null -s -w "%{http_code}" -X GET "$url" \
        -H "Authorization: Bearer $HF_TOKEN" \
        -H "Content-Type: application/json")

    # Check if the token is valid
    if [ "$response" -eq 200 ]; then
        return 0
    else
        return 1
    fi
}

function provisioning_has_valid_civitai_token() {
    [[ -n "$CIVITAI_TOKEN" ]] || return 1
    url="https://civitai.com/api/v1/models?hidden=1&limit=1"

    response=$(curl -o /dev/null -s -w "%{http_code}" -X GET "$url" \
        -H "Authorization: Bearer $CIVITAI_TOKEN" \
        -H "Content-Type: application/json")

    # Check if the token is valid
    if [ "$response" -eq 200 ]; then
        return 0
    else
        return 1
    fi
}

# Download from $1 URL to $2 directory. Can optionally rename to $3
function provisioning_download() {
    url=$1
    dir=$2
    filename=$3
    
    if [[ -n $HF_TOKEN && $url =~ ^https://([a-zA-Z0-9_-]+\.)?huggingface\.co(/|$|\?) ]]; then
        auth_token="$HF_TOKEN"
    elif [[ -n $CIVITAI_TOKEN && $url =~ ^https://([a-zA-Z0-9_-]+\.)?civitai\.com(/|$|\?) ]]; then
        auth_token="$CIVITAI_TOKEN"
    fi
    
    if [[ -n "$filename" ]]; then
        if [[ -n "$auth_token" ]]; then
            wget --header="Authorization: Bearer $auth_token" -qnc -O "$dir/$filename" --show-progress -e dotbytes="4M" "$url"
        else
            wget -qnc -O "$dir/$filename" --show-progress -e dotbytes="4M" "$url"
        fi
    else
        if [[ -n "$auth_token" ]]; then
            wget --header="Authorization: Bearer $auth_token" -qnc --content-disposition --show-progress -e dotbytes="4M" -P "$dir" "$url"
        else
            wget -qnc --content-disposition --show-progress -e dotbytes="4M" -P "$dir" "$url"
        fi
    fi
}

# Allow user to disable provisioning if they started with a script they didn't want
if [[ ! -f /.noprovisioning ]]; then
    provisioning_start
fi
