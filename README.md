<p align="center" style="display: flex; justify-content: center; flex-wrap: wrap; ">
  <img src="exemple/00115-3758984262.png" style="width: 24%;" />
  <img src="exemple/00127-3306616736.png" style="width: 24%; " />
  <img src="exemple/00140-1746999371.png" style="width: 24%;" />
  <img src="exemple/00154-2440198289.png" style="width: 24%;" />
</p>

###### *Exemple d'utilisation avec ControlNet*

# Stable Diffusion Server Installer

## Ce projet propose un script Bash automatisé pour déployer entièrement Stable Diffusion WebUI (AUTOMATIC1111) sur un serveur Ubuntu, avec :

- **Installation de Python, CUDA, cuDNN et pilotes NVIDIA**
  
- **Configuration via un fichier JSON unique : install_config.json**
  - Téléchargement automatique de modèles (checkpoints, LoRA, VAE)
  - Ajout d’extensions et de leurs modèles liés
- **Lancement résilient de la WebUI avec redémarrage automatique**
  

## Contenu du dépôt
- [serveur_script.sh](serveur_script.sh) – Script principal d'installation
- [install_config.json](install_config.json) – Fichier de configuration des modèles et extensions
  

## Prérequis
- Système : Ubuntu 22.04
- Accès : Privilèges sudo requis
- GPU NVIDIA (optionnel mais recommandé) pour accélération CUDA
- Connexion Internet stable
  

## Étapes automatisées par serveur_script.sh

### [0/9] Mises à jour système & dépendances

Installation des bibliothèques nécessaires pour la compilation de Python et l’environnement graphique

### [1/9] Installation de Python 3.10.6

Téléchargement, compilation et installation si Python 3.10.6 est absent. Pip est également installé si nécessaire.

### [2/9] Clonage du dépôt Stable Diffusion WebUI

Le dépôt [https://github.com/AUTOMATIC1111/stable-diffusion-webui](https://github.com/AUTOMATIC1111/stable-diffusion-webui) est cloné dans :

- /root/StableDiffusionServer/ par défaut

- `--folder-install=/votre/chemin` si précisé

### [3/9] Installation des modèles, extensions, LoRA, VAE ([install_config.json](install_config.json))

#### Authentification (auth)
Cette section contient les clés d'API pour accéder à des plateformes tierces :

- *Hugging Face* : Accès aux modèles hébergés sur Hugging Face via un token personnel.

- *Civitai* : Accès aux modèles depuis Civitai avec un token d'authentification.

#### Modèles (models)
Liste des modèles principaux à télécharger automatiquement. Chaque entrée contient :

- *enabled* : Active ou désactive le téléchargement.

- *url* : Lien direct vers le fichier .safetensors du modèle.

#### Extensions (extensions)
Télécharge et installe des extensions pour la Web UI, comme ControlNet ou IP-Adapter.

- *enabled* : Active le téléchargement de l’extension.

- *url* : Lien vers le dépôt GitHub de l’extension.

- *models* (optionnel) : Liste des modèles nécessaires à l’extension, avec leurs liens directs.

#### LoRA
Modules de fine-tuning légers à charger dans l’interface. Chaque LoRA contient :

- *enabled*

- *url* : vers un fichier .safetensors.

#### VAE

Les VAE (Variational Autoencoders) permettent d’améliorer la qualité des images générées.

### [4/9] Création d’un environnement virtuel Python

Création d’un venv dans `../venv`

Installation des dépendances Python via requirements.txt

### [5/9] Installation des pilotes NVIDIA

Détection du GPU via lspci

Installation du driver recommandé (nvidia-driver-535) si GPU détecté

### [6/9] Installation de CUDA Toolkit 12.9

Ajout du dépôt CUDA officiel

Installation de `cuda-toolkit-12-9`

### [7/9] Installation de cuDNN

Vérifie si cuDNN est installé

Sinon : installe à partir du dépôt NVIDIA

### [8/9] Installation de PyTorch & xFormers (CUDA 12.1)

Installe :

- `torch==2.1.2`,

- `torchvision`,

- `torchaudio`,

- `xformers==0.0.23.post1`
via le dépôt officiel compatible CUDA 12.1

Supprime les versions précédentes de PyTorch si besoin

Ajoute aussi insightface (détection visage)

### [9/9] Lancement automatique de la WebUI

Lance la WebUI avec des arguments adaptés à un serveur

`--share --listen --api --enable-insecure-extension-access --xformers --no-half-vae --medvram`

Redémarre automatiquement si la WebUI plante

## Options du script

`--folder-install=/chemin`	=> Change le répertoire d’installation

`--no-install`	=> Ignore l’installation des modèles, LoRA, VAE, extensions



