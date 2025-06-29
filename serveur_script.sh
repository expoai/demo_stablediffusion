#!/bin/bash

echo "[0/7] Mise à jour et installation des outils de base..."
sudo apt update
sudo apt install -y wget git build-essential libssl-dev zlib1g-dev \
    libncurses5-dev libncursesw5-dev libreadline-dev libsqlite3-dev \
    libgdbm-dev libdb5.3-dev libbz2-dev libexpat1-dev liblzma-dev tk-dev libffi-dev unzip libgl1 libglib2.0-0

#Vérification Python 3.10.6
echo "[1/7] Vérification de Python 3.10.6..."
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

PYTHON=python3.10

# Cloner le dépôt stable-diffusion-webui
echo "[2/7] Vérification du dépôt stable-diffusion-webui..."
REDIRECT="/root"
PROJECT_DIR=$REDIRECT/StableDiffusionServer

# Vérifier si un flag --project-dir est passé
for arg in "$@"; do
  if [[ "$arg" == --folder-install=* ]]; then
    PROJECT_DIR="${arg#*=}/StableDiffusionServer"
    echo "Utilisation d'un dossier personnalisé pour PROJECT_DIR : $PROJECT_DIR"
  fi
done

echo "Utilisation du dossier pour PROJECT_DIR : $PROJECT_DIR"
mkdir -p "$PROJECT_DIR"
cd "$PROJECT_DIR"

if [ ! -d "stable-diffusion-webui" ]; then
    git clone https://github.com/AUTOMATIC1111/stable-diffusion-webui.git
else
    echo "Le dépôt stable-diffusion-webui existe déjà." 
fi

cd stable-diffusion-webui || exit

# SKIP Installations de tout les ajouts (models/extensions/Lora)
SKIP_EXTENSIONS=false

for arg in "$@"; do
  if [[ "$arg" == "--no-install" ]]; then
    SKIP_EXTENSIONS=true
  fi
done

if [ "$SKIP_EXTENSIONS" = false ]; then

    # Vérification des modèles
    echo "[3/7] Vérification des modèles..."
    MODEL_DIR="models/Stable-diffusion"
    mkdir -p "$MODEL_DIR"

    MODEL_PRUNED="$MODEL_DIR/v1-5-pruned-emaonly.safetensors"
    if [ ! -f "$MODEL_PRUNED" ]; then
        wget -O "$MODEL_PRUNED" "https://huggingface.co/runwayml/stable-diffusion-v1-5/resolve/main/v1-5-pruned-emaonly.safetensors"
    else
        echo "Modèle v1-5-pruned-emaonly déjà présent."
    fi

    MODEL_BNB="$MODEL_DIR/isometric-skeumorphic-3d-bnb.safetensors"
    if [ ! -f "$MODEL_BNB" ]; then
        wget -O "$MODEL_BNB" "https://huggingface.co/multimodalart/isometric-skeumorphic-3d-bnb/resolve/main/isometric-skeumorphic-3d-bnb.safetensors"
    else
        echo "Modèle Isometric Skeumorphic déjà présent."
    fi

    MODEL_SDXL="$MODEL_DIR/sd_xl_base_1.0.safetensors"
    if [ ! -f "$MODEL_SDXL" ]; then
        wget -O "$MODEL_SDXL" "https://huggingface.co/stabilityai/stable-diffusion-xl-base-1.0/resolve/main/sd_xl_base_1.0.safetensors"
    else
        echo "Modèle Stable Diffusion XL base déjà présent."
    fi

    MODEL_SDXL_REFINER="$MODEL_DIR/sd_xl_refiner_1.0.safetensors"
    if [ ! -f "$MODEL_SDXL_REFINER" ]; then
        wget -O "$MODEL_SDXL_REFINER" "https://huggingface.co/stabilityai/stable-diffusion-xl-refiner-1.0/resolve/main/sd_xl_refiner_1.0.safetensors"
    else
        echo "Modèle Stable Diffusion XL base refiner déjà présent."
    fi

    MODEL_NOVA="$MODEL_DIR/novaCartoonXL_v10.safetensors"
    if [ ! -f "$MODEL_NOVA" ]; then
        wget -O "$MODEL_NOVA" "https://civitai.green/api/download/models/1777060?type=Model&format=SafeTensor&size=pruned&fp=fp16"
    else
        echo "Modèle Nova Cartoon v10 déjà présent."
    fi

    VAE_DIR="models/VAE"

    VAE_SDXL_VAE="$VAE_DIR/sdxl_vae.safetensors"
    if [ ! -f "$VAE_SDXL_VAE" ]; then
        wget -O "$VAE_SDXL_VAE" "https://huggingface.co/stabilityai/sdxl-vae/resolve/main/sdxl_vae.safetensors"
    else
        echo "Modèle Nova Cartoon v10 déjà présent."
    fi

    # Exemple de gestion de flag dans ton script
    SKIP_EXTENSIONS=false

    for arg in "$@"; do
      if [[ "$arg" == "--no-extensions" ]]; then
        SKIP_EXTENSIONS=true
      fi
    done
    
    cd "$PROJECT_DIR/stable-diffusion-webui" || exit
    EXT_DIR="extensions"
    CONTROLNET_DIR="$EXT_DIR/sd-webui-controlnet"
        
    echo "[4/7] Installation des extensions..."
    if [ "$SKIP_EXTENSIONS" = false ]; then
      echo "Installation des extensions..."

        # [4/7] Installation de l'extension sd-webui-controlnet
        echo "Installation de l'extension sd-webui-controlnet..."

        if [ ! -d "$CONTROLNET_DIR" ]; then
            echo "Clonage de sd-webui-controlnet..."
            git clone https://github.com/Mikubill/sd-webui-controlnet "$CONTROLNET_DIR"
        else
            echo "Extension sd-webui-controlnet déjà installée."
        fi

        # Téléchargement automatique du modèle controlnet-canny-sdxl-1.0
        echo "Installation du modèle ControlNet : controlnet-canny-sdxl-1.0..."

        CONTROLNET_MODEL_DIR="$CONTROLNET_DIR/models"
        mkdir -p "$CONTROLNET_MODEL_DIR"

        MODEL_NAME="controlnet-canny-sdxl-1.0.safetensors"
        MODEL_PATH="$CONTROLNET_MODEL_DIR/$MODEL_NAME"

        if [ ! -f "$MODEL_PATH" ]; then
            echo "Téléchargement de $MODEL_NAME..."
            wget -O "$MODEL_PATH" "https://huggingface.co/lllyasviel/ControlNet-v1-1/resolve/main/models/$MODEL_NAME"
        else
            echo "Modèle $MODEL_NAME déjà présent."
        fi

    else
        echo "Extensions désactivées (flag --no-extensions)"
        
        if [ -d "$EXT_DIR" ]; then
            echo "Suppression du contenu du dossier extensions..."
            rm -rf "$EXT_DIR"/* 
        fi
    fi


    # Installation des loRA 
    echo "[5/8] Vérification des LoRA..."


    LORA_DIR="models/Lora"
    mkdir -p "$LORA_DIR"
    LORA_FILE="$LORA_DIR/isometric-skeumorphic-3d-bnb.safetensors"
    if [ ! -f "$LORA_FILE" ]; then
      wget -O "$LORA_FILE" \
        "https://huggingface.co/multimodalart/isometric-skeumorphic-3d-bnb/resolve/main/isometric-skeumorphic-3d-bnb.safetensors"
    else
      echo "LoRA isometric-skeumorphic déjà présent."
    fi
    
else
      echo "Installations désactivées (flag --no-install)"
fi

# Création et activation de l'environnement virtuel
echo "[5/7] Création et activation de l'environnement virtuel Python..."
if [ ! -d "../venv" ]; then
    $PYTHON -m venv ../venv
fi
source ../venv/bin/activate

# Mise à jour pip/setuptools/wheel dans le venv
pip install --upgrade pip setuptools wheel

# Installation des dépendances Python spécifiques au projet
if [ -f "requirements.txt" ]; then
    pip install -r requirements.txt
fi

# Installation des pilotes NVIDIA + CUDA pour PyTorch GPU
echo "[5.5/7] Installation des pilotes NVIDIA et CUDA..."

# Vérifie si le GPU NVIDIA est détecté
if lspci | grep -i nvidia > /dev/null; then
    echo "GPU NVIDIA détecté. Installation des pilotes..."

    # Installation du driver NVIDIA recommandé
    sudo apt install -y nvidia-driver-535

    echo "Redémarrage recommandé après installation du pilote NVIDIA."

else
    echo "Aucun GPU NVIDIA détecté. Passage en mode CPU."
fi

# Installation de PyTorch avec CUDA 12.1 + xFormers compatible
echo "[6/7] Installation de PyTorch et xFormers compatibles GPU..."

# Mise à jour de pip
pip install --upgrade pip

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
fi


# Lancement de Stable Diffusion WebUI avec options CPU / mémoire réduite
echo "[7/7] Lancement de Stable Diffusion WebUI..."
export COMMANDLINE_ARGS="--share --listen --port 7860 --api --enable-insecure-extension-access --xformers --no-half-vae --medvram"
python launch.py
