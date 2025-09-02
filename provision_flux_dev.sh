#!/bin/bash
# Provisioning script para ComfyUI + FLUX.1-dev + LoRAs
# Usa: HF_TOKEN (obligatorio para FLUX.1-dev), PROVISIONING_SCRIPT (URL de este script)
set -euo pipefail

log() { echo -e "[provision] $*"; }

# --- Rutas base ---
WORKSPACE="${WORKSPACE:-/workspace}"
COMFY_DIR="${WORKSPACE}/ComfyUI"
CKPT_DIR="${COMFY_DIR}/models/checkpoints"
CLIP_DIR="${COMFY_DIR}/models/clip"
T5_DIR="${COMFY_DIR}/models/t5"
LORA_DIR="${COMFY_DIR}/models/loras"
TMP_DIR="${WORKSPACE}/.provision_tmp"

mkdir -p "$CKPT_DIR" "$CLIP_DIR" "$T5_DIR" "$LORA_DIR" "$TMP_DIR"

# --- Activar entorno Python principal ---
if [ -f /venv/main/bin/activate ]; then
  # shellcheck disable=SC1091
  . /venv/main/bin/activate
  log "Entorno /venv/main activado."
else
  log "AVISO: no se encontró /venv/main; continúo sin activar venv."
fi

# --- Comprobar huggingface-cli ---
if ! command -v huggingface-cli >/dev/null 2>&1; then
  log "Instalando huggingface_hub[cli]..."
  pip install --no-cache-dir -q "huggingface_hub[cli]"
fi

# --- Comprobar HF_TOKEN ---
if [ "${HF_TOKEN:-}" = "" ]; then
  log "ERROR: HF_TOKEN no está definido. Define HF_TOKEN en las variables de entorno de la instancia."
  exit 1
fi

# --- Descargar FLUX.1-dev ---
# Repo oficial: black-forest-labs/FLUX.1-dev
# Descargamos todos los .safetensors + metadatos útiles al directorio de checkpoints.
log "Descargando FLUX.1-dev desde Hugging Face..."
huggingface-cli download \
  black-forest-labs/FLUX.1-dev \
  --token "$HF_TOKEN" \
  --local-dir "$TMP_DIR/flux1-dev" \
  --include "*.safetensors" "*.json" "*.txt" || {
    log "ERROR descargando FLUX.1-dev. ¿Aceptaste la licencia y es válido el HF_TOKEN?"
    exit 1
  }

# Mover el/los .safetensors al directorio de checkpoints (nombre estándar: flux1-dev.safetensors si existe)
if compgen -G "$TMP_DIR/flux1-dev/*.safetensors" > /dev/null; then
  # Si existe un archivo llamado exactamente flux1-dev.safetensors, usarlo; si no, mover todos.
  if [ -f "$TMP_DIR/flux1-dev/flux1-dev.safetensors" ]; then
    mv -f "$TMP_DIR/flux1-dev/flux1-dev.safetensors" "$CKPT_DIR/flux1-dev.safetensors"
    log "Checkpoint colocado en $CKPT_DIR/flux1-dev.safetensors"
  else
    # Mueve cualquier .safetensors que haya (por compatibilidad con futuras publicaciones)
    mv -f "$TMP_DIR/flux1-dev/"*.safetensors "$CKPT_DIR/"
    log "Checkpoints colocados en $CKPT_DIR/"
  fi
else
  log "ERROR: no se encontraron .safetensors en la descarga de FLUX.1-dev."
  exit 1
fi

# Guardar también metadatos útiles en el propio repo local (opcional)
mkdir -p "$CKPT_DIR/flux1-dev-meta"
shopt -s nullglob
for f in "$TMP_DIR/flux1-dev/"*.json "$TMP_DIR/flux1-dev/"*.txt; do
  cp -f "$f" "$CKPT_DIR/flux1-dev-meta/" || true
done
shopt -u nullglob

# --- (Opcional) Encoders / tokenizers ---
# Muchos workflows de ComfyUI con FLUX funcionan solo con el checkpoint.
# Si algún workflow te pide encoders específicos, descomenta y ajusta las líneas siguientes.
#
# 1) Ejemplo: descargar CLIP al directorio models/clip
# log "Descargando encoder CLIP (ejemplo, ajusta al repo/archivo correcto si tu workflow lo pide)..."
# huggingface-cli download \
#   openai/clip-vit-large-patch14 \
#   --local-dir "$CLIP_DIR/clip-vit-large-patch14" \
#   --include "*.json" "*.txt" "*.bin" "*.pt"
#
# 2) Ejemplo: descargar T5 al directorio models/t5
# log "Descargando T5 (ejemplo, ajusta al repo/archivo correcto si tu workflow lo pide)..."
# huggingface-cli download \
#   google/t5-v1_1-xxl \
#   --local-dir "$T5_DIR/t5-v1_1-xxl" \
#   --include "*.json" "*.txt" "*.model" "*.sentencepiece" "*.bin"

# --- Descarga de LoRAs definidas por el usuario ---
# Añade URLs (HF raw, Civitai, etc.) a la variable LORA_URLS como array o como cadena separada por espacios.
# Ejemplo en Vast (Environment Variables):
# LORA_URLS="https://huggingface.co/usuario/repo/resolve/main/mi_lora.safetensors https://civitai.com/api/download/models/12345"
#
# También puedes crear un archivo lista en ${WORKSPACE}/lora_urls.txt y poner una URL por línea.
download_lora() {
  local url="$1"
  local fname
  fname="$(basename "${url%%\?*}")"  # quita querystring para nombres limpios
  if [ -z "$fname" ] || [[ "$fname" != *.safetensors ]]; then
    # Nombre de reserva si el endpoint no revela el nombre
    fname="lora_$(date +%s%N).safetensors"
  fi
  log "Descargando LoRA: $url"
  # Intentar con curl y fallback a wget
  if command -v curl >/dev/null 2>&1; then
    curl -L --fail --retry 5 --retry-delay 3 -o "$LORA_DIR/$fname" "$url"
  else
    wget --tries=5 --retry-connrefused --waitretry=3 -O "$LORA_DIR/$fname" "$url"
  fi
  log "LoRA guardada en $LORA_DIR/$fname"
}

# 1) LORA_URLS desde variable de entorno (espacios o saltos de línea)
if [ "${LORA_URLS:-}" != "" ]; then
  # Convertir en líneas
  printf "%s" "$LORA_URLS" | tr ' ' '\n' | while read -r line; do
    [ -z "$line" ] && continue
    download_lora "$line"
  done
fi

# 2) LORA_URLS desde archivo ${WORKSPACE}/lora_urls.txt (una URL por línea)
if [ -f "$WORKSPACE/lora_urls.txt" ]; then
  while IFS= read -r url; do
    [ -z "$url" ] && continue
    download_lora "$url"
  done < "$WORKSPACE/lora_urls.txt"
fi

# --- Limpieza ---
rm -rf "$TMP_DIR"
log "Provisioning completado. FLUX.1-dev y LoRAs listos."
