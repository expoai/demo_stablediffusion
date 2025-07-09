#!/bin/bash
set -e

# CONFIGURATION
REPO_URL="https://github.com/comfyanonymous/ComfyUI.git"
DIR_NAME="StableDiffusionServer"
PORT=8080
VENV_DIR="venv"
CONFIG_FILE="/home/ubuntu/demo_stablediffusion/install_config.json"  # JSON à placer dans le dossier parent

# Vérification et installation de Python 3.12 et python3.12-venv si manquants
if ! command -v python3.12 &> /dev/null; then
  echo "Installation de Python 3.12 et python3.12-venv..."
  sudo apt update
  sudo apt install -y python3.12 python3.12-venv
else
  echo "Python 3.12 déjà installé."
fi

# Création du dossier principal
mkdir -p "$DIR_NAME"
cd "$DIR_NAME"

# Clone ComfyUI
echo "Vérification du dossier ComfyUI..."
if [ ! -d ComfyUI ]; then
  echo "Clonage du dépôt ComfyUI..."
  git clone "$REPO_URL"
else
  echo "Dossier ComfyUI déjà présent, on continue."
fi

cd ComfyUI || exit

# Création des dossiers s'ils n'existent pas
mkdir -p models/checkpoints models/vae models/loras models/controlnet custom_nodes

# Auth Civitai et HuggingFace
echo "Lecture de l'authentification dans le fichier $CONFIG_FILE..."
CIVITAI_TOKEN=$(jq -r '.auth.civitai.token' "$CONFIG_FILE")
HUGGINGFACE_TOKEN=$(jq -r '.auth.huggingface.token' "$CONFIG_FILE")

AUTH_HEADER=""
if jq -e '.auth.civitai.enabled' "$CONFIG_FILE" | grep -q true; then
  AUTH_HEADER="Authorization: Bearer $CIVITAI_TOKEN"
fi

# Fonction de téléchargement
download_if_enabled() {
  local section="$1"
  local folder="$2"

  echo "Installation de $section..."
  jq -r ".$section | to_entries[] | select(.value.enabled == true) | [.key, .value.url] | @tsv" "$CONFIG_FILE" | \
  while IFS=$'\t' read -r name url; do
    format=$(basename "$url" | cut -d '?' -f 1 | awk -F. '{print $NF}')
    if [[ "$format" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
        format="safetensors"
    fi
    dest="models/$folder/$name.$format"
    if [[ -f "$dest" ]]; then
      echo "$name déjà installé dans $dest, téléchargement ignoré."
      continue
    fi
    echo "Téléchargement de $name dans $dest"
    if [[ "$url" == *huggingface.co* && -n "$HUGGINGFACE_TOKEN" ]]; then
      curl -L -H "Authorization: Bearer $HUGGINGFACE_TOKEN" "$url" -o "$dest"
    elif [[ -n "$AUTH_HEADER" && "$url" == *civitai* ]]; then
      curl -L -H "$AUTH_HEADER" "$url" -o "$dest"
    else
      curl -L "$url" -o "$dest"
    fi
  done
}

# Téléchargement des modèles
download_if_enabled "models" "checkpoints"
download_if_enabled "VAE" "vae"
download_if_enabled "lora" "loras"
download_if_enabled "difmodel" "diffusion_models"
download_if_enabled "textencoder" "text_encoders"

# Extensions
echo "Installation des extensions..."
jq -r '.extensions | to_entries[] | select(.value.enabled == true) | [.key, .value.url] | @tsv' "$CONFIG_FILE" | \
while IFS=$'\t' read -r name url; do
  EXT_DIR="custom_nodes/$name"
  if [ ! -d "$EXT_DIR" ]; then
    echo "Clonage de l'extension $name"
    git clone "$url" "$EXT_DIR"
  else
    echo "Extension $name déjà présente"
 fi

  # Modèles spécifiques à l'extension
  jq -r --arg name "$name" '.extensions[$name].models // {} | to_entries[] | select(.value.enabled == true) | [.key, .value.url] | @tsv' "$CONFIG_FILE" | \
  while IFS=$'\t' read -r subname suburl; do
    filename=$(basename "$suburl")
    dest="models/controlnet/$filename"
    if [[ -f "$dest" ]]; then
      echo "$subname déjà installé dans $dest, téléchargement ignoré."
      continue
    fi
    echo "Téléchargement de $subname dans $dest"
    curl -L "$suburl" -o "$dest"
  done
done

# Venv
echo "Configuration de l'environnement virtuel..."
if [ ! -d "$VENV_DIR" ]; then
  echo "Création du venv..."
  python3.12 -m venv "$VENV_DIR"
  source "$VENV_DIR/bin/activate"
  pip install --upgrade pip
  pip install -r requirements.txt
else
  echo "venv déjà présent, activation..."
  source "$VENV_DIR/bin/activate"
fi

# Vérification de PyTorch
echo "Vérification de l'installation de PyTorch..."
if ! python3 -c "import torch" &> /dev/null; then
  echo "PyTorch non détecté, installation en cours..."

  # Vérifie la présence de GPU NVIDIA (CUDA)
  if command -v nvidia-smi &> /dev/null; then
    echo "NVIDIA GPU détecté, installation de PyTorch avec support CUDA..."
    pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu121
  else
    echo "Pas de GPU NVIDIA détecté, installation de PyTorch CPU-only..."
    pip install torch torchvision torchaudio
  fi

else
  echo "PyTorch est déjà installé."
fi

# Lancement ComfyUI
echo "Lancement de ComfyUI..."
nohup python3 main.py --listen 0.0.0.0 --port $PORT > comfyui.log 2>&1 &

# Affichage de l'adresse publique
echo ""
echo "ComfyUI est maintenant en cours d'exécution."
IPV4=$(curl -s ipv4.icanhazip.com)
echo "URL d'accès : http://$IPV4:$PORT"
