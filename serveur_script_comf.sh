#!/bin/bash
set -e

# CONFIGURATION
REPO_URL="https://github.com/comfyanonymous/ComfyUI.git"
DIR_NAME="/home/ubuntu/StableDiffusionServer"
PORT=8080
VENV_DIR="venv"
CONFIG_FILE="/home/ubuntu/demo_stablediffusion/install_config.json"  # JSON à placer dans le dossier parent

sudo apt update

# Fonction pour installer avec correction automatique des paquets cassés
safe_apt_install() {
  local packages="$*"
  if ! sudo apt install -y $packages; then
    echo "Échec de l'installation de $packages. Tentative de réparation avec --fix-broken..."
    sudo apt --fix-broken install -y
    echo "Nouvelle tentative d'installation de $packages..."
    sudo apt install -y $packages
  fi
}

if ! command -v python3.10 &> /dev/null || [[ $(python3.10 --version) != *"3.10.6"* ]]; then
    echo "Python 3.10.6 non détecté. Installation en cours..."
    cd /tmp
    wget https://www.python.org/ftp/python/3.10.6/Python-3.10.6.tgz
    tar -xf Python-3.10.6.tgz
    cd Python-3.10.6
    ./configure --enable-optimizations
    make -j$(nproc)
    sudo make altinstall
    cd ~
    echo "Python 3.10.6 installé."
else
    echo "Python 3.10.6 déjà installé."
fi

# Installer pip pour python3.10 si nécessaire
if ! python3.10 -m pip --version &> /dev/null; then
    echo "Installation de pip pour Python 3.10..."
    wget https://bootstrap.pypa.io/get-pip.py -O /tmp/get-pip.py
    python3.10 /tmp/get-pip.py
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

# Installation des pilotes NVIDIA + CUDA pour PyTorch GPU

#sudo apt install -y pciutils

# Vérifie si le GPU NVIDIA est détecté
if lspci | grep -i nvidia > /dev/null; then
    echo "GPU NVIDIA détecté. Installation des pilotes..."
    # Installation du driver NVIDIA recommandé
    safe_apt_install -y nvidia-driver-535
    echo "Redémarrage recommandé après installation du pilote NVIDIA."
else
    echo "Aucun GPU NVIDIA détecté. Passage en mode CPU."
fi

# Vérification de la version actuelle de PyTorch
PYTORCH_VERSION=$(python3 -c "import torch; print(torch.__version__)" 2>/dev/null || echo "not_installed")
if [[ "$PYTORCH_VERSION" == "2.1.2+cu121" ]]; then
    echo " PyTorch 2.1.2 est déjà installé. Aucune action nécessaire."
else
    echo " PyTorch $PYTORCH_VERSION détecté. Installation de PyTorch 2.1.2 avec CUDA 12.1..."

    echo "Nettoyage des versions précédentes de torch, torchvision, torchaudio, xformers..."
    pip uninstall -y torch torchvision torchaudio xformers

    echo "Installation de PyTorch 2.1.2 avec support CUDA 12.1..."
    pip install torch==2.1.2 torchvision==0.16.2 torchaudio==2.1.2 --index-url https://download.pytorch.org/whl/cu121

    echo "Installation de xFormers stable compatible avec CUDA 12.1..."
    pip install xformers==0.0.23.post1 --index-url https://download.pytorch.org/whl/cu121
    
    pip install insightface
fi

# Lancement ComfyUI
echo "Lancement de ComfyUI..."
nohup python3 main.py --listen 0.0.0.0 --port $PORT > comfyui.log 2>&1 &

# Affichage de l'adresse publique
echo ""
echo "ComfyUI est maintenant en cours d'exécution."
IPV4=$(curl -s ipv4.icanhazip.com)
echo "URL d'accès : http://$IPV4:$PORT"
