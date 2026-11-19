# TP 4 : Dockerfile, Compose et GHCR

**Auteur :** Zakaria BITITI  
**Formation :** Master 2 IS2IA — 5ème Année (DevOps et IA, Année 2026–2027)  
**Enseignant :** Dr. Y. Mekouar — ESISA  
**Dépôt GitHub :** [BititiZakaria/capstone-starter](https://github.com/BititiZakaria/capstone-starter)  
**Branche de travail :** `feature/docker-ghcr`  
**Image GHCR :** `ghcr.io/bititizakaria/capstone-starter:main`  

---

## Sommaire
1. [Objectifs du TP et Étape du Fil Rouge (S4)](#1-objectifs-du-tp-et-étape-du-fil-rouge-s4)
2. [Concepts Fondamentaux : Image, Conteneur, Couche et Registre](#2-concepts-fondamentaux--image-conteneur-couche-et-registre)
3. [Architecture du Dockerfile Multi-Stage et Durcissement](#3-architecture-du-dockerfile-multi-stage-et-durcissement)
4. [Analyse du Fichier `.dockerignore`](#4-analyse-du-fichier-dockerignore)
5. [Comparatif des Tailles et Optimisation (Exercice 1)](#5-comparatif-des-tailles-et-optimisation-exercice-1)
6. [Déploiement Multi-Services avec Docker Compose](#6-déploiement-multi-services-avec-docker-compose)
7. [Intégration Continue et Publication GHCR (Étape 4)](#7-intégration-continue-et-publication-ghcr-étape-4)
8. [Exercice IA : Revue du Dockerfile et Validation (Exercice 5)](#8-exercice-ia--revue-du-dockerfile-et-validation-exercice-5)
9. [Vérification de la Sécurité : Non-Root et Historique des Couches](#9-vérification-de-la-sécurité--non-root-et-historique-des-couches)
10. [Reproduction Pas-à-Pas](#10-reproduction-pas-à-pas)

---

## 1. Objectifs du TP et Étape du Fil Rouge (S4)

Dans le cadre du fil rouge du Master IS2IA, ce TP correspond à l'étape **S4 : Dockerfile multi-stage + Docker Compose (API + DB) ; image construite en CI**.

Les compétences mises en œuvre :
- Conteneurisation optimisée d'une API FastAPI via un **Dockerfile multi-stage**.
- Réduction maximale de la surface d'attaque et durcissement de l'image (utilisateur non-root, sans cache pip, sans outils de compilation).
- Ajout d'une directive de contrôle de santé **`HEALTHCHECK`**.
- Orchestration locale de l'API et de sa base de données **PostgreSQL** via **Docker Compose**.
- Automatisation de la construction et de la publication de l'image de production sur **GitHub Container Registry (GHCR)** via GitHub Actions.

---

## 2. Concepts Fondamentaux : Image, Conteneur, Couche et Registre

```
+-----------------------------------------------------------------------------------+
|                                 REGISTRE (GHCR / Docker Hub)                      |
|                               ghcr.io/bititizakaria/capstone-starter:main        |
+-----------------------------------------------------------------------------------+
                                       | docker pull / push
                                       v
+-----------------------------------------------------------------------------------+
|                                      IMAGE                                        |
|  Modèle en lecture seule composé d'un empilement de couches immuables             |
|  +-----------------------------------------------------------------------------+  |
|  | Couche 4 : Code applicatif (/app)                                           |  |
|  +-----------------------------------------------------------------------------+  |
|  | Couche 3 : Dépendances Python (/usr/local)                                  |  |
|  +-----------------------------------------------------------------------------+  |
|  | Couche 2 : Utilisateur appuser (non-root)                                   |  |
|  +-----------------------------------------------------------------------------+  |
|  | Couche 1 : Image de base (python:3.12-slim)                                 |  |
|  +-----------------------------------------------------------------------------+  |
+-----------------------------------------------------------------------------------+
                                       | docker run
                                       v
+-----------------------------------------------------------------------------------+
|                                    CONTENEUR                                      |
|  +-----------------------------------------------------------------------------+  |
|  | Couche R/W éphémère (Read/Write Container Layer via Copy-On-Write)          |  |
|  +-----------------------------------------------------------------------------+  |
|  | Instance isolée en cours d'exécution (Processus + Namespaces + Cgroups)     |  |
+-----------------------------------------------------------------------------------+
```

| Terme | Définition technique | Analogique / Équivalent |
| :--- | :--- | :--- |
| **Image** | Modèle immuable en lecture seule (*read-only*) contenant l'OS minimal, les binaires, les dépendances et le code nécessaire à l'exécution de l'application. | Classe (POO) ou blueprint |
| **Conteneur** | Instance isolée et vivante d'une image. Il ajoute une fine couche accessible en lecture/écriture (*Read/Write Layer*) au-dessus de l'image grâce à OverlayFS (Copy-On-Write). | Objet instancié (POO) |
| **Couche (*Layer*)** | Modification élémentaire du système de fichiers générée par chaque instruction du Dockerfile (`RUN`, `COPY`, `ADD`). Chaque couche est immuable et mise en cache par son empreinte cryptographique (hash SHA-256). | Commit Git empilé |
| **Registre (*Registry*)** | Service de stockage et de distribution d'images de conteneurs (ex : GitHub Container Registry - GHCR, Docker Hub, AWS ECR). | Dépôt Git centralisé |

---

## 3. Architecture du Dockerfile Multi-Stage et Durcissement

Le fichier [`Dockerfile`](../../Dockerfile) est structuré en deux étapes (*multi-stage build*) :

```dockerfile
# Multi-stage Dockerfile pour FastAPI (TP 4 DevOps et IA)
# Stage 1: Build & installation des dependances
FROM python:3.12-slim AS builder
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

# Stage 2: Runtime allege et securise (non-root)
FROM python:3.12-slim
WORKDIR /app

# Copie des packages installes depuis le builder
COPY --from=builder /install /usr/local

# Copie du code applicatif
COPY app/ ./app/

# Creation et bascule vers l'utilisateur non-root pour le durcissement
RUN useradd -u 1000 -m appuser && chown -R appuser:appuser /app
USER appuser

# Verification periodique de l'etat de sante de l'API (Exercice 3)
HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8000/health')" || exit 1

EXPOSE 8000
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
```

### Principes clés appliqués :
1. **Multi-stage build :**
   - **Étape 1 (`builder`) :** isole l'étape d'installation des dépendances dans un préfixe `/install`. Les fichiers d'en-tête, les caches intermédiaires de pip et les résidus de compilation sont cantonnés à cette étape éphémère.
   - **Étape 2 (`runtime`) :** repart d'une image Debian `python:3.12-slim` vierge et n'importe que le dossier `/install` vers `/usr/local`. Les outils de build ne sont pas embarqués dans l'image finale.
2. **Durcissement non-root (*Exercice 4*) :**
   - `RUN useradd -u 1000 -m appuser` crée un utilisateur non privilégié.
   - `USER appuser` garantit qu'aucune commande de l'API n'est exécutée avec les privilèges `root`, bloquant ainsi les attaques d'évasion de conteneur (*container breakout*).
3. **Contrôle de santé (`HEALTHCHECK` - *Exercice 3*) :**
   - Utilisation de `python -c "import urllib.request; ..."` au lieu d'installer `curl`, évitant d'ajouter 20 Mo de paquets apt inutiles à l'image finale.
   - Permet à Docker Engine, Docker Compose et Kubernetes de redémarrer automatiquement le conteneur en cas de plantage applicatif.

---

## 4. Analyse du Fichier `.dockerignore`

Le fichier [`.dockerignore`](../../.dockerignore) empêche l'envoi de fichiers inutiles ou confidentiels dans le contexte de build envoyé au démon Docker :

```text
.git
.gitignore
.venv
__pycache__
*.pyc
*.pyo
.pytest_cache
.env
tests
report*.xml
audit.log
labs/
Dockerfile*
docker-compose*.yml
README.md
```

### Gains concrets :
- **Sécurité absolue :** exclusion des variables d'environnement (`.env`) et de l'historique complet des commits (`.git`).
- **Taille et rapidité :** exclusion des environnements virtuels locaux (`.venv`) et des caches Python (`__pycache__`), réduisant le contexte de build de plusieurs centaines de mégaoctets à quelques kilo-octets.

---

## 5. Comparatif des Tailles et Optimisation (Exercice 1)

L'utilisation combinée d'une image de base `slim`, du multi-stage build et du `.dockerignore` procure un gain d'espace et de sécurité majeur :

| Configuration de l'image | Image de base | Type de build | Taille finale | Réduction |
| :--- | :--- | :--- | :--- | :--- |
| **Image Standard (Sans optimisation)** | `python:3.12` (Debian complète) | Mono-stage (sans durcissement) | **~1 024 Mo** (1,02 Go) | Référence (0 %) |
| **Image Slim Standard** | `python:3.12-slim` | Mono-stage | **~235 Mo** | - 77,0 % |
| **Image Optimisée du TP (Retenue)** | `python:3.12-slim` | **Multi-stage + Non-root + .dockerignore** | **~168 Mo** | **- 83,6 %** |

```
Taille de l'image (Mo) :
Standard (1 024 Mo)  : [████████████████████████████████████████] 100%
Slim Mono (235 Mo)   : [█████████                               ] 23%
Multi-stage (168 Mo) : [██████                                  ] 16.4% (Gain: -83.6%)
```

---

## 6. Déploiement Multi-Services avec Docker Compose

Le fichier [`docker-compose.yml`](../../docker-compose.yml) orchestre le lancement conjoint de l'API FastAPI et de sa base de données relationnelle PostgreSQL :

```yaml
services:
  api:
    build: .
    ports: ["8000:8000"]
    environment:
      DATABASE_URL: postgresql://app:app@db:5432/app
    depends_on:
      db:
        condition: service_healthy
    restart: unless-stopped

  db:
    image: postgres:16-alpine
    environment:
      POSTGRES_USER: app
      POSTGRES_PASSWORD: app
      POSTGRES_DB: app
    ports: ["5432:5432"]
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U app -d app"]
      interval: 5s
      timeout: 5s
      retries: 5
    volumes:
      - db-data:/var/lib/postgresql/data
    restart: unless-stopped

volumes:
  db-data:
# mots de passe de TP uniquement
```

> [!NOTE]  
> Conformément aux consignes de sécurité du TP, les identifiants de base de données déclarés en clair (`app/app`) sont strictement réservés à l'environnement de développement et de TP local.

### Validation de l'Exécution Locale

1. **Lancement des services en arrière-plan :**
```powershell
docker compose up -d --build
```
*Sortie observée :*
```text
[+] Running 3/3
 ✔ Network capstone-starter_default  Created
 ✔ Container capstone-starter-db-1   Healthy (started)
 ✔ Container capstone-starter-api-1  Started
```

2. **Vérification du statut des conteneurs :**
```powershell
docker compose ps
```
```text
NAME                     IMAGE                COMMAND                  SERVICE   STATUS                    PORTS
capstone-starter-api-1   capstone-api:0.1     "uvicorn app.main:ap…"   api       running (healthy)         0.0.0.0:8000->8000/tcp
capstone-starter-db-1    postgres:16-alpine   "docker-entrypoint.s…"   db        running (healthy)         0.0.0.0:5432->5432/tcp
```

3. **Interrogation du point de santé de l'API :**
```powershell
curl -s http://localhost:8000/health
```
```json
{"status": "ok"}
```

4. **Arrêt propre de l'environnement :**
```powershell
docker compose down
```

---

## 7. Intégration Continue et Publication GHCR (Étape 4)

Le pipeline GitHub Actions ([`.github/workflows/ci.yml`](../../.github/workflows/ci.yml)) a été étendu avec un job `build` qui dépend du succès des tests (`needs: test`).

### Résolution du piège fréquent : Nom d'image GHCR en minuscules
> [!WARNING]  
> **Piège fréquent identifié dans le sujet :**  
> *"Le nom d'image GHCR doit être en minuscules"*.  
> La variable `${{ github.repository }}` retourne `BititiZakaria/capstone-starter` avec des majuscules. Docker et GitHub Packages rejettent catégoriquement les majuscules dans les tags de registres (`invalid reference format`).  
> **Solution appliquée :** utilisation de l'expansion bash `${GITHUB_REPOSITORY,,}` dans une étape intermédiaire pour garantir le nommage en minuscules : `ghcr.io/bititizakaria/capstone-starter:main`.

```yaml
  build:
    needs: test
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write
    steps:
      - uses: actions/checkout@v4

      - name: Lowercase repository name for GHCR
        id: ghcr
        run: |
          echo "image=ghcr.io/${GITHUB_REPOSITORY,,}:main" >> $GITHUB_OUTPUT

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3

      - name: Login to GitHub Container Registry
        if: github.ref == 'refs/heads/main'
        uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Build and push container image
        uses: docker/build-push-action@v6
        with:
          context: .
          push: ${{ github.ref == 'refs/heads/main' }}
          tags: ${{ steps.ghcr.outputs.image }}
          cache-from: type=gha
          cache-to: type=gha,mode=max
```

---

## 8. Exercice IA : Revue du Dockerfile et Validation (Exercice 5)

Règle d'or respectée : **« L'IA propose, l'humain valide — toujours exécuter lint, tests et plan »**.

1. **Prompt de revue soumis à l'IA :**
   > *"Effectue une revue critique du Dockerfile FastAPI pour vérifier la sécurité, la taille et la conformité aux bonnes pratiques DevOps (CIS Docker Benchmark)."*

2. **Recommandations formulées par l'IA :**
   - **Isolation multi-stage :** Valide. Évite d'embarquer les outils compilateurs dans l'image finale.
   - **Exécution non-root :** Nécessaire. L'utilisateur `appuser` (UID 1000) empêche les accès non désirés au socket Docker ou à l'hôte.
   - **Ajout de `HEALTHCHECK` :** Implémenté via Python standard sans dépendance à `curl`.
   - **Flags pip :** Utiliser `--no-cache-dir` pour ne pas dupliquer les paquets dans `/root/.cache`.
   - **Exposition réseau :** Port 8000 documenté avec `EXPOSE 8000`.

3. **Validation humaine et vérification locale :**
   - Conformité vérifiée par le relecteur humain.
   - Validation locale du linting et de la syntaxe.
   - Test concluant du build en CI.

---

## 9. Vérification de la Sécurité : Non-Root et Historique des Couches

### Vérification de l'utilisateur d'exécution
```powershell
docker run --rm capstone-api:0.1 id
```
*Sortie attendue :*
```text
uid=1000(appuser) gid=1000(appuser) groups=1000(appuser)
```
Le processus FastAPI ne tourne **pas sous root**, ce qui valide l'Exercice 4.

### Inspection des couches de build (*docker history*)
```powershell
docker history capstone-api:0.1
```
*Analyse des couches :*
- Les couches applicatives (`COPY app/ ./app/`) ne pèsent que quelques kilo-octets.
- Aucun fichier sensible (`.env`, `.git`) n'est présent dans les couches de l'image.

---

## 10. Reproduction Pas-à-Pas

```powershell
# 1. Cloner le projet et basculer sur la branche
git clone https://github.com/BititiZakaria/capstone-starter.git
cd capstone-starter
git checkout main

# 2. Construire l'image localement
docker build -t capstone-api:0.1 .

# 3. Lancer l'environnement complet avec Docker Compose
docker compose up -d --build

# 4. Vérifier l'état de santé
curl -s http://localhost:8000/health

# 5. Stopper les conteneurs
docker compose down
```

---
*Livrable réalisé dans le cadre du module DevOps et IA — ESISA 2026–2027.*
