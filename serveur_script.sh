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
SKIP_INSTALL=false

for arg in "$@"; do
  if [[ "$arg" == "--no-install" ]]; then
    SKIP_INSTALL=true
  fi
done

if [ "$SKIP_INSTALL" = false ]; then


    CONFIG_FILE="/notebooks/install_config.json"
    EXT_DIR="extensions"
    MODEL_DIR="models/Stable-diffusion"
    LORA_DIR="models/Lora"
    VAE_DIR="models/VAE"

    # Vérifie que jq est installé
    if ! command -v jq &>/dev/null; then
      sudo apt install -y jq
    fi

    # Crée les dossiers si besoin
    mkdir -p "$EXT_DIR" "$MODEL_DIR" "$LORA_DIR" "$VAE_DIR"
    
    # Récupération des tokens
    if jq -e '.auth.huggingface.enabled==true' "$CONFIG_FILE" > /dev/null; then
        HF_TOKEN=$(jq -r '.auth.huggingface.token' "$CONFIG_FILE")
    fi
    if jq -e '.auth.civitai.enabled==true' "$CONFIG_FILE" > /dev/null; then
        CA_TOKEN=$(jq -r '.auth.civitai.token' "$CONFIG_FILE")
    fi

    curl_exit_code=$?

    echo "[MODELS]"
    jq -r '.models | to_entries[] | select(.value.enabled == true) | "\(.key) \(.value.url)"' "$CONFIG_FILE" | while read -r name url; do
      FILE="$MODEL_DIR/$name.safetensors"
      if [ ! -f "$FILE" ]; then
        echo "Téléchargement du modèle : $name"
        if [[ "$url" == https://huggingface.co/* ]]; then
          wget --header="Authorization: Bearer $HF_TOKEN" -O "$FILE" "$url"
        elif [[ "$url" == https://civitai.* ]]; then
          MODEL_ID=$(echo "$url" | grep -oP '/models/\K[0-9]+')
          URL=$(curl -s -H "Authorization: Bearer $CA_TOKEN" "https://civitai.com/api/v1/model-versions/$MODEL_ID" | jq -r '.files[] | select(.type=="Model") | .downloadUrl')
          curl_output=$(curl -sS --fail -o "$FILE" "$URL" 2>&1)
          curl -L -H "Authorization: Bearer $CA_TOKEN" -o "$FILE" "$URL"
          if [[ $curl_exit_code -eq 3 || "$curl_output" == *"URL using bad/illegal format or missing URL"* ]]; then
            curl -L -H "Authorization: Bearer $CA_TOKEN" -o "$FILE" "$url"
          fi
        else
          echo "Le model n'a pas été trouvé"
        fi
      else
        echo "Modèle $name déjà présent."
      fi
    done

    echo "[EXTENSIONS + MODELS LIÉS]"
    jq -c '.extensions | to_entries[] | select(.value.enabled == true)' "$CONFIG_FILE" | while read -r entry; do
      NAME=$(echo "$entry" | jq -r '.key')
      URL=$(echo "$entry" | jq -r '.value.url')
      DIR="$EXT_DIR/$NAME"

      if [ ! -d "$DIR" ]; then
        echo "Clonage extension : $NAME"
        git clone "$URL" "$DIR"
      else
        echo "Extension $NAME déjà installée."
      fi

      # Téléchargement des modèles liés à l'extension
      echo "$entry" | jq -c '.value.models // {} | to_entries[] | select(.value.enabled == true)' | while read -r model_entry; do
        MODEL_NAME=$(echo "$model_entry" | jq -r '.key')
        MODEL_URL=$(echo "$model_entry" | jq -r '.value.url')
        MODEL_FORMAT=$(echo "$model_entry" | jq -r '.value.url' | awk -F. '{print $NF}')
        MODEL_PATH="$DIR/models/$MODEL_NAME.$MODEL_FORMAT"

        mkdir -p "$DIR/models"
        if [ ! -f "$MODEL_PATH" ]; then
          echo "Téléchargement modèle lié : $MODEL_NAME pour $NAME"
          wget -O "$MODEL_PATH" "$MODEL_URL"
        else
          echo "Modèle lié $MODEL_NAME déjà présent pour $NAME"
        fi
      done
    done

    echo "[LORAS]"
    jq -r '.lora | to_entries[] | select(.value.enabled == true) | "\(.key) \(.value.url)"' "$CONFIG_FILE" | while read -r name url; do
      FILE="$LORA_DIR/$name.safetensors"
      if [ ! -f "$FILE" ]; then
        echo "Téléchargement du LoRA : $name"
        wget -O "$FILE" "$url"
      else
        echo "LoRA $name déjà présent."
      fi
    done
    
    echo "[VAE]"
    jq -r '.VAE | to_entries[] | select(.value.enabled == true) | "\(.key) \(.value.url)"' "$CONFIG_FILE" | while read -r name url; do
      FILE="$VAE_DIR/$name.safetensors"
      if [ ! -f "$FILE" ]; then
        echo "Téléchargement du VAE : $name"
        wget -O "$FILE" "$url"
      else
        echo "VAE $name déjà présent."
      fi
    done

    
else
      echo "Installations désactivées (flag --no-install)"
fi

# Création et activation de l'environnement virtuel
echo "[5/7] Création et activation de l'environnement virtuel Python..."
if [ ! -d "../venv" ]; then
    $PYTHON -m venv ../venv
    
    source ../venv/bin/activate
    
    # Mise à jour pip/setuptools/wheel dans le venv
    pip install --upgrade pip setuptools wheel

    # Installation des dépendances Python spécifiques au projet
    if [ -f "requirements.txt" ]; then
        pip install -r requirements.txt
    fi
fi
source ../venv/bin/activate

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

# Vérifie si CUDA Toolkit 12.9 est déjà installé
if ! nvcc --version 2>/dev/null | grep -q "release 12.9"; then
  echo "Installation de CUDA Toolkit 12.9..."
  wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/cuda-keyring_1.1-1_all.deb
  sudo dpkg -i cuda-keyring_1.1-1_all.deb
  sudo apt-get update
  sudo apt-get -y install cuda-toolkit-12-9
else
  echo "CUDA Toolkit 12.9 déjà installé."
fi

# Vérifie si cuDNN est déjà installé
if ! dpkg -l | grep -q "cudnn"; then
  echo "Installation de cuDNN..."
  wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/cuda-keyring_1.1-1_all.deb
  sudo dpkg -i cuda-keyring_1.1-1_all.deb
  sudo apt-get update
  sudo apt-get -y install cudnn
else
  echo "cuDNN déjà installé."
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
    
    pip install insightface
fi


# Lancement de Stable Diffusion WebUI avec options CPU / mémoire réduite
echo "[7/7] Lancement de Stable Diffusion WebUI..."
export COMMANDLINE_ARGS="--share --listen --api --enable-insecure-extension-access --xformers --no-half-vae --medvram"
    
while true; do
    echo ">> Lancement de la WebUI..."
    
    # Lancement avec les arguments passés au script (ex: --listen --xformers etc.)
    python launch.py

    echo "!!! La WebUI s'est arrêtée. Redémarrage dans 3 secondes..."
    sleep 3
done
