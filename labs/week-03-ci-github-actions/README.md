# TP 3 : Premier Pipeline CI — GitHub Actions

**Auteur :** Zakaria BITITI  
**Formation :** Master 2 IS2IA — 5ème Année (DevOps et IA, Année 2026–2027)  
**Enseignant :** Dr. Y. Mekouar — ESISA  
**Dépôt GitHub :** [BititiZakaria/capstone-starter](https://github.com/BititiZakaria/capstone-starter)  
**Branche de travail :** `ci/github-actions-workflow`  
**Pull Request :** [PR #4 : ci: integrate GitHub Actions workflow with matrix, cache and artifact](https://github.com/BititiZakaria/capstone-starter/pull/4)  

---

## Sommaire
1. [Objectifs du TP et Notions Clés](#1-objectifs-du-tp-et-notions-clés)
2. [Concepts Fondamentaux : CI vs CD (Delivery) vs CD (Deployment)](#2-concepts-fondamentaux--ci-vs-cd-delivery-vs-cd-deployment)
3. [Comparatif des Outils CI/CD : GitHub Actions vs Jenkins vs GitLab CI](#3-comparatif-des-outils-cicd--github-actions-vs-jenkins-vs-gitlab-ci)
4. [Évaluation de la Fiabilité d'un Pipeline](#4-évaluation-de-la-fiabilité-dun-pipeline)
5. [Architecture et Fichiers de Configuration du Pipeline](#5-architecture-et-fichiers-de-configuration-du-pipeline)
   - [Workflow Principal : `.github/workflows/ci.yml`](#workflow-principal--githubworkflowsciyml)
   - [Workflow Réutilisable : `.github/workflows/reusable-test.yml`](#workflow-réutilisable--githubworkflowsreusable-testyml)
6. [Démonstration CI : Run Rouge, Diagnostic IA et Run Vert](#6-démonstration-ci--run-rouge-diagnostic-ia-et-run-vert)
   - [Étape "Casser" : Run Rouge (Exercice 1)](#étape-casser--run-rouge-exercice-1)
   - [Exercice IA : Diagnostic et Validation Humaine (Exercice 5)](#exercice-ia--diagnostic-et-validation-humaine-exercice-5)
   - [Étape "Réparer" : Run Vert et Artefacts (Étape 3 & Exercice 2)](#étape-réparer--run-vert-et-artefacts-étape-3--exercice-2)
7. [Mesure du Gain du Cache (Exercice 3 & Étape 5)](#7-mesure-du-gain-du-cache-exercice-3--étape-5)
8. [Configuration de la Protection de Branche (Étape 4)](#8-configuration-de-la-protection-de-branche-étape-4)
9. [Sécurité et Bonnes Pratiques](#9-sécurité-et-bonnes-pratiques)
10. [Reproduction Pas-à-Pas](#10-reproduction-pas-à-pas)

---

## 1. Objectifs du TP et Notions Clés

Dans le cadre du fil rouge (API FastAPI, tests, Docker, Kubernetes, monitoring et agent ops), ce TP met en place le premier pipeline d'**Intégration Continue (CI)** avec **GitHub Actions**.

Les objectifs atteints dans ce TP :
- Automatisation du linting (`ruff`) et des tests unitaires (`pytest`) sur chaque Pull Request et sur chaque push sur `main`.
- Mise en œuvre d'une matrice multi-environnements testant **Python 3.11** et **Python 3.12**.
- Optimisation du temps d'exécution grâce à la **mise en cache des dépendances pip**.
- Export et archivage du rapport de tests JUnit XML sous forme d'**artefact téléchargeable** (`actions/upload-artifact@v4`) avec condition d'exécution `if: always()`.
- Découpage modulaire via un **workflow réutilisable** (`on: workflow_call`).
- Application stricte de la règle d'assistance par IA : *"L'IA propose, l'humain valide — toujours exécuter lint, tests et plan"*.
- Protection de la branche `main` exigeant le succès des statuts de CI (`required status checks`) avant tout merge.

---

## 2. Concepts Fondamentaux : CI vs CD (Delivery) vs CD (Deployment)

| Phase | Acronyme | Définition | Déclencheur typique | Rôle & Bénéfice |
| :--- | :--- | :--- | :--- | :--- |
| **Intégration Continue** | **CI** | Automatisation de la compilation, du linting, des tests unitaires et d'intégration à chaque commit ou PR. | `push`, `pull_request` | Détecter les régressions au plus tôt (*Fail Fast*), garantir que la branche principale est toujours saine. |
| **Livraison Continue** | **CD** (*Continuous Delivery*) | Automatisation de l'empaquetage (image Docker, release) et déploiement automatique sur un environnement de staging. Le déploiement en production nécessite une **validation humaine manuelle** (approbation en 1 clic). | Merge sur `main`, création de tag/release | Préparer des livrables prêts pour la production à tout moment avec contrôle humain. |
| **Déploiement Continu** | **CD** (*Continuous Deployment*) | Tout commit validé par les tests de la CI/CD traverse l'ensemble du pipeline et est **automatiquement déployé en production**, sans intervention humaine. | Merge validé sur `main` | Accélération maximale du *Time-to-Market*, feedback immédiat des utilisateurs finaux, exige une couverture de tests irréprochable et un rollback automatisé. |

---

## 3. Comparatif des Outils CI/CD : GitHub Actions vs Jenkins vs GitLab CI

| Critère d'évaluation | GitHub Actions | Jenkins | GitLab CI/CD |
| :--- | :--- | :--- | :--- |
| **Modèle d'hébergement** | SaaS natif géré par GitHub (possibilité de runners *self-hosted*). | Auto-hébergé (*on-premise* ou cloud IaaS sur VM/K8s). Maintenance serveur à charge complète. | SaaS (GitLab.com) ou Auto-hébergé (*GitLab Self-Managed*). |
| **Syntaxe de configuration** | Fichiers YAML déclaratifs situés dans `.github/workflows/`. | Fichier `Jenkinsfile` (Groovy scripté ou déclaratif). | Fichier YAML déclaratif `.gitlab-ci.yml` à la racine. |
| **Intégration au dépôt** | Totale et native au dépôt GitHub (PRs, Checks API, Issues, Releases). | Via plugins et webhooks GitHub/GitLab/Bitbucket. Configuration souvent complexe. | Totale et native à GitLab (Merge Requests, Registry Docker, Packages). |
| **Écosystème & Marketplace** | **GitHub Marketplace** immense (+20 000 actions prêtes à l'emploi réutilisables). | Écosystème historique riche en plugins, mais maintenance lourde et risques de compatibilité. | GitLab CI Templates et composants de catalogue, intégration Docker très poussée. |
| **Gestion des Runners** | Runners managés fournis gratuitement (avec quota mensuel) + runners auto-hébergés. | Agents gérés manuellement (VMs, conteneurs Docker, pods Kubernetes). | GitLab Runners (Docker, Kubernetes, Shell, SSH) managés ou auto-hébergés. |
| **Facilité d'adoption** | **Excellente** : aucune infrastructure à installer, démarrage immédiat en YAML. | **Moyenne à difficile** : administration complexe, gestion des mises à jour des plugins. | **Très bonne** : fluide pour les utilisateurs de l'écosystème GitLab. |
| **Matrice de tests & Cache** | Intégrée nativement (`strategy.matrix`, `actions/cache` ou `cache: pip`). | Possible mais demande des configurations de pipelines parallèles en Groovy. | Intégrée nativement (`parallel: matrix`, mot-clé `cache:` par job). |
| **Cas d'usage privilégié** | Projets hébergés sur GitHub, open-source, startups et architectures cloud modernes. | Grandes entreprises avec infrastructures héritées (*legacy*), besoins stricts *on-premise*. | Entreprises utilisant la suite GitLab tout-en-un (du code au monitoring). |

---

## 4. Évaluation de la Fiabilité d'un Pipeline

La robustesse et la rapidité d'un pipeline CI reposent sur trois piliers fondamentaux :

1. **Durée d'exécution (*Pipeline Duration*) :**
   - Un pipeline doit donner un feedback aux développeurs en **moins de 5 à 10 minutes**.
   - Si le pipeline est trop lent, les développeurs cessent d'attendre les résultats avant de passer à une autre tâche, ce qui brise le flux de travail (*flow state*) et augmente le temps d'intégration.
   - Leviers d'optimisation : parallélisme via matrices de jobs, mise en cache des dépendances (pip, npm, maven), suppression des étapes redondantes.

2. **Gestion des tests instables (*Flaky Tests*) :**
   - Un test "flaky" réussit ou échoue de façon aléatoire sans modification de code (lié à des dépendances réseau externes, de la concurrence temporelle `time.sleep`, ou des fuites d'état en base de données).
   - Conséquence : perte totale de confiance de l'équipe dans la CI ("*c'est un faux positif, relance le build*").
   - Solutions : isolation stricte des tests (mocks, bases de données de test éphémères), détection et quarantaine des tests instables, interdiction des dépendances réseau directes dans les tests unitaires.

3. **Stratégie et Invalidation du Cache :**
   - Le cache accélère l'installation des dépendances en évitant les téléchargements répétitifs.
   - Risque : utiliser un cache obsolète masquant un problème de compatibilité avec une nouvelle sous-dépendance.
   - Solution : clé de cache basée sur le hash des fichiers de dépendances (`hashFiles('**/requirements*.txt')`). Si un fichier change, le cache est invalidé et recréé proprement.

---

## 5. Architecture et Fichiers de Configuration du Pipeline

### Workflow Principal : `.github/workflows/ci.yml`

Ce workflow s'exécute sur chaque création ou mise à jour de Pull Request ainsi que sur les pushs vers la branche `main`. Il configure une matrice pour tester simultanément l'API sur Python 3.11 et 3.12, utilise le cache pip, exécute le linting avec `ruff`, lance `pytest` avec sortie JUnit XML, et publie les artefacts de test même en cas d'échec (`if: always()`).

```yaml
name: ci

on:
  pull_request:
  push:
    branches: [main]

jobs:
  test:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        python-version: ["3.11", "3.12"]
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version: ${{ matrix.python-version }}
          cache: pip
      - run: pip install -r requirements.txt -r requirements-dev.txt
      - run: ruff check .
      - run: pytest -q --junitxml=report-${{ matrix.python-version }}.xml
      - uses: actions/upload-artifact@v4
        if: always()
        with:
          name: test-report-${{ matrix.python-version }}
          path: report-${{ matrix.python-version }}.xml
```

### Workflow Réutilisable : `.github/workflows/reusable-test.yml`

Répondant à l'**Exercice 4**, ce workflow utilise l'événement `workflow_call` permettant à d'autres pipelines ou dépôts de factoriser et mutualiser l'étape d'exécution des tests.

```yaml
name: reusable-test

on:
  workflow_call:
    inputs:
      python-version:
        required: true
        type: string
        description: "Version de Python pour l'environnement de test"

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version: ${{ inputs.python-version }}
          cache: pip
      - run: pip install -r requirements.txt -r requirements-dev.txt
      - run: ruff check .
      - run: pytest -q --junitxml=report-${{ inputs.python-version }}.xml
      - uses: actions/upload-artifact@v4
        if: always()
        with:
          name: test-report-${{ inputs.python-version }}
          path: report-${{ inputs.python-version }}.xml
```

---

## 6. Démonstration CI : Run Rouge, Diagnostic IA et Run Vert

### Étape "Casser" : Run Rouge (Exercice 1)

Pour valider le déclenchement et la détection d'erreurs par le pipeline, une régression a été introduite volontairement dans `tests/test_main.py` :
```python
def test_predict():
    # Échec volontaire pour déclencher un run rouge dans la CI
    assert client.get("/predict?x=1").json()["label"] == "wrong_label_error"
```

Ce commit a été poussé sur la branche `ci/github-actions-workflow`, et la **Pull Request #4** a été ouverte.

- **Lien du Run CI Rouge :** [GitHub Actions Run #44496957962](https://github.com/BititiZakaria/capstone-starter/actions/runs/44496957962)
- **Statut :** `completed` / `failure` ❌
- **Trace d'erreur extraite des logs de la CI :**
```text
================================== FAILURES ===================================
________________________________ test_predict _________________________________

    def test_predict():
>       assert client.get("/predict?x=1").json()["label"] == "wrong_label_error"
E       AssertionError: assert 'positive' == 'wrong_label_error'
E         
E         - wrong_label_error
E         + positive

tests/test_main.py:16: AssertionError
=========================== short test summary info ===========================
FAILED tests/test_main.py::test_predict - AssertionError: assert 'positive' == 'wrong_label_error'
1 failed, 1 passed in 0.97s
##[error]Process completed with exit code 1.
```
- **Validation du comportement de l'artefact :**
Grâce à la directive `if: always()`, l'étape `actions/upload-artifact@v4` a été exécutée même après l'échec de pytest :
  - Artefact 3.12 généré : `test-report-3.12` (ID: 14514684416)
  - Artefact 3.11 généré : `test-report-3.11` (ID: 14514619747)

---

### Exercice IA : Diagnostic et Validation Humaine (Exercice 5)

Conformément à la règle d'or :  
> **"L'IA propose, l'humain valide — toujours exécuter lint, tests et plan."**

1. **Question posée à l'IA :**
   > *"Le job pytest a échoué sur l'étape de prédiction avec l'erreur `AssertionError: assert 'positive' == 'wrong_label_error'`. Diagnostique l'origine de l'échec et propose un correctif propre."*

2. **Diagnostic fourni par l'IA :**
   - **Origine :** Dans `app/main.py`, la route `/predict` implémente :
     `"label": "positive" if x >= 0 else "negative"`.
   - Lors de l'appel `/predict?x=1`, la valeur de `x` est `1.0 >= 0`, le serveur retourne donc légitimement `{"input": 1.0, "label": "positive"}`.
   - Le test dans `tests/test_main.py` attendait la chaîne `"wrong_label_error"`, provoquant une `AssertionError`.
   - **Correction proposée :** Remplacer `"wrong_label_error"` par `"positive"`.

3. **Validation humaine et vérification locale avant commit :**
   - Revue manuelle de la logique métier dans `app/main.py`.
   - Exécution locale du linter :
     ```powershell
     python -m ruff check .
     # Résultat : All checks passed!
     ```
   - Exécution locale des tests unitaires :
     ```powershell
     python -m pytest -q
     # Résultat : 2 passed in 1.17s
     ```
   - Décision humaine : proposition validée, commit autorisé.

---

### Étape "Réparer" : Run Vert et Artefacts (Étape 3 & Exercice 2)

Le test a été corrigé dans le commit `6ac0c2c` :
```python
def test_predict():
    assert client.get("/predict?x=1").json()["label"] == "positive"
```

Le push a automatiquement relancé la CI sur la Pull Request #4.

- **Lien du Run CI Vert :** [GitHub Actions Run #44497789737](https://github.com/BititiZakaria/capstone-starter/actions/runs/44497789737)
- **Statut :** `completed` / `success` ✅
- **Détails des jobs exécutés :**
  - Job `test (3.11)` : [Job #135469309689](https://github.com/BititiZakaria/capstone-starter/actions/runs/44497789737/job/135469309689) — **Succès** (15s)
  - Job `test (3.12)` : [Job #135469310225](https://github.com/BititiZakaria/capstone-starter/actions/runs/44497789737/job/135469310225) — **Succès** (20s)
- **Artefacts disponibles au téléchargement sur GitHub Actions :**
  - `test-report-3.11` (ID: 14515572313, 355 octets)
  - `test-report-3.12` (ID: 14515797634, 356 octets)

---

## 7. Mesure du Gain du Cache (Exercice 3 & Étape 5)

L'action `actions/setup-python@v5` configurée avec `cache: pip` sauvegarde automatiquement le répertoire de cache de pip entre deux exécutions consécutives du runner.

### Tableau Comparatif des Performances

| Métrique observée | Run 1 : Sans Cache (Cache Miss) | Run 2 : Avec Cache (Cache Hit) | Gain obtenu |
| :--- | :--- | :--- | :--- |
| **Run ID** | `#44496957962` | `#44497789737` | — |
| **Étape `pip install` (Python 3.11)** | 7,1 s | 4,8 s | **- 32 % de temps** |
| **Étape `pip install` (Python 3.12)** | 6,3 s | 4,2 s | **- 33 % de temps** |
| **Téléchargement réseau des roues (wheels)** | Téléchargement complet depuis PyPI | Restauration locale depuis le cache GitHub | **100 % de trafic réseau économisé** |
| **Durée totale du job (3.11)** | 21 s | 15 s | **- 28 %** |

**Analyse technique :**
Lors du premier run, pip télécharge l'intégralité des binaires (FastAPI, Uvicorn, Pydantic, HTTPX, Ruff, Pytest, Prometheus Client). Lors du second run, l'étape `actions/setup-python` restaure l'archive du cache pip directement sur le runner. Pip détecte les roues déjà présentes dans son cache local et procède immédiatement à l'installation sans requête HTTP externe. Sur un projet comportant des dépendances volumineuses (comme PyTorch, TensorFlow ou Scikit-Learn), le gain passe généralement de plusieurs minutes à quelques secondes.

---

## 8. Configuration de la Protection de Branche (Étape 4)

Afin d'empêcher tout déploiement ou merge de code non testé ou cassé sur la branche de production `main`, une règle de protection a été configurée :

1. **Accès :** `Settings > Branches > Branch protection rules` sur la branche `main`.
2. **Options activées :**
   - **Require a pull request before merging :** aucun push direct n'est autorisé sur `main` (`git push origin main` est rejeté).
   - **Require approvals :** au moins 1 approbation par un relecteur est exigée.
   - **Require status checks to pass before merging :**
     - Check requis 1 : `test (3.11)`
     - Check requis 2 : `test (3.12)`
   - **Require branches to be up to date before merging :** la PR doit être rebasée ou fusionnée avec le dernier état de `main`.

Vérification API de la règle appliquée sur le dépôt :
```json
{
  "required_status_checks": {
    "strict": true,
    "contexts": [
      "test (3.11)",
      "test (3.12)"
    ]
  },
  "required_pull_request_reviews": {
    "required_approving_review_count": 1
  }
}
```

---

## 9. Sécurité et Bonnes Pratiques

- **Aucun secret committé :** le fichier `.env` contenant les variables locales est exclu par le `.gitignore` et aucun jeton d'accès n'est affiché dans les logs ou scripts.
- **Interdiction de `echo` des secrets :** conformément aux recommandations DevOps, aucune commande `echo` n'affiche de variable sensible dans les étapes de build.
- **Épinglage des versions majeures des actions :** utilisation de tags de version éprouvés (`actions/checkout@v4`, `actions/setup-python@v5`, `actions/upload-artifact@v4`) pour éviter les régressions en amont.
- **Qualité du code et formatting :** code source nettoyé selon la PEP 8 et validé avec `ruff check .` (résolution des imports désordonnés et remplacement des anciens formats de chaînes par des f-strings).

---

## 10. Reproduction Pas-à-Pas

Pour cloner et reproduire l'environnement localement :

```powershell
# 1. Cloner le dépôt et basculer sur la branche CI
git clone https://github.com/BititiZakaria/capstone-starter.git
cd capstone-starter
git checkout ci/github-actions-workflow

# 2. Créer l'environnement virtuel et installer les dépendances
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt -r requirements-dev.txt

# 3. Exécuter le linter
ruff check .

# 4. Lancer les tests unitaires avec génération du rapport JUnit XML
pytest -q --junitxml=report.xml
```

---
*Livrable réalisé dans le cadre du module DevOps et IA — ESISA 2026–2027.*
