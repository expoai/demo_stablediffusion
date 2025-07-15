#!/bin/bash
set -e

# CONFIGURATION
REPO_URL="https://github.com/comfyanonymous/ComfyUI.git"
DIR_NAME="/home/ubuntu/StableDiffusionServer"
PORT=8080
VENV_DIR="venv"
CONFIG_FILE="/home/ubuntu/demo_stablediffusion/install_config.json"  # JSON à placer dans le dossier parent

sudo apt update
sudo apt install -y build-essential \
                    zlib1g-dev libncurses5-dev libgdbm-dev libnss3-dev libssl-dev \
                    libreadline-dev libffi-dev curl libbz2-dev libsqlite3-dev \
                    libncursesw5-dev libdb5.3-dev libexpat1-dev liblzma-dev tk-dev \
                    unzip libgl1 libglib2.0-0

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
else
    echo "mise à jour de pip"
    pip3.10 install --upgrade pip
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
download_if_enabled "clpvision" "clip_vision"

# Extensions
echo "Installation des extensions..."
jq -r '.extensions | to_entries[] | select(.value.enabled == true) | [.key, .value.url] | @tsv' "$CONFIG_FILE" | \
while IFS=$'\t' read -r name url; do
  EXT_DIR="custom_nodes/$name"
  if [ ! -d "$EXT_DIR" ]; then
    echo "Clonage de l'extension $name"
    git clone "$url" "$EXT_DIR"
    if [[ -d "$EXT_DIR/$name/requirement.txt" ]]; then
      pip install -r requirement.txt
    fi
  else
    echo "Extension $name déjà présente"
 fi

  # Modèles spécifiques à l'extension
  jq -r --arg name "$name" '.extensions[$name].models // {} | to_entries[] | select(.value.enabled == true) | [.key, .value.url] | @tsv' "$CONFIG_FILE" | \
  while IFS=$'\t' read -r subname suburl; do
    filename=$(basename "$suburl")
    if [[ "$name" == "ComfyUI_IPAdapter_plus" ]]; then
        extension=ipadapter
    else
        extension=controlnet
    fi
    mkdir -p "models/$extension"
    echo "models/$extension"
    dest="models/$extension/$filename"
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
  sudo python3.10 -m venv "$VENV_DIR"
  source "$VENV_DIR/bin/activate"
  pip install --upgrade pip
  pip install -r requirements.txt
  python3.10 -m pip install onnxruntime-gpu
else
  echo "venv déjà présent, activation..."
  source "$VENV_DIR/bin/activate"
fi

echo "mise à niveau de numpy"
pip install "numpy<2.0" --force-reinstall --no-cache-dir

# Installation des pilotes NVIDIA + CUDA pour PyTorch GPU

#sudo apt install -y pciutils

# Vérifie si le GPU NVIDIA est détecté
if lspci | grep -i nvidia > /dev/null; then
    echo "GPU NVIDIA détecté. Installation des pilotes..."
    # Installation du driver NVIDIA recommandé
    safe_apt_install -y nvidia-driver-535
    echo "Vérification de la détection GPU après installation..."
    if ! nvidia-smi; then
        echo "Le driver NVIDIA semble ne pas être actif. Un redémarrage est requis."
        sudo reboot
        exit 0
    fi
else
    echo "Aucun GPU NVIDIA détecté. Passage en mode CPU."
fi

# Détection de la version de PyTorch actuellement installée
PYTORCH_VERSION=$(python3 -c "import torch; print(torch.__version__)" 2>/dev/null || echo "not_installed")

# Détection de la version de PyTorch actuellement installée
PYTORCH_VERSION=$(python3 -c "import torch; print(torch.__version__)")

echo "PyTorch détecté : $PYTORCH_VERSION"

# Nettoyage si une ancienne version de xformers est présente
echo "Suppression de xformers (pour réinstallation propre)..."
pip uninstall -y xformers

# Réinstallation de xformers compatible avec torch actuel
echo "Installation de xformers compatible avec torch $PYTORCH_VERSION..."
pip install xformers --no-cache-dir

# Vérification de succès
if [[ $? -ne 0 ]]; then
    echo "Échec de l'installation de xformers. Veuillez vérifier les logs ci-dessus."
    exit 1
fi

# Installation de insightface (utile dans ComfyUI pour certaines nodes)
echo "Installation d'InsightFace..."
pip install insightface

echo "xformers et insightface installés avec succès pour torch $PYTORCH_VERSION"


# Lancement ComfyUI
echo "Lancement de ComfyUI..."
nohup python3 main.py --listen 0.0.0.0 --port $PORT > comfyui.log 2>&1 &

# Affichage de l'adresse publique
echo ""
echo "ComfyUI est maintenant en cours d'exécution."
IPV4=$(curl -s ipv4.icanhazip.com)
echo "URL d'accès : http://$IPV4:$PORT"
