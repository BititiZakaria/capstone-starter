# TP 6 : Configuration, Sondes et HPA

**Auteur :** Zakaria BITITI  
**Formation :** Master 2 IS2IA — 5ème Année (DevOps et IA, Année 2026–2027)  
**Enseignant :** Dr. Y. Mekouar — ESISA  
**Dépôt GitHub :** [BititiZakaria/capstone-starter](https://github.com/BititiZakaria/capstone-starter)  
**Branche de travail :** `feature/k8s-config-sondes-hpa-helm`  
**Image conteneur :** `capstone-api:0.1`  

---

## Sommaire
1. [Objectifs du TP et Étape du Fil Rouge (S6)](#1-objectifs-du-tp-et-étape-du-fil-rouge-s6)
2. [Externalisation de la Configuration : ConfigMap et Secret](#2-externalisation-de-la-configuration--configmap-et-secret)
   - [Manifeste `k8s/config.yaml`](#manifeste-k8sconfigyaml)
   - [Injection Globale via `envFrom`](#injection-globale-via-envfrom)
   - [Lecture dans l'API FastAPI (Exercice 1)](#lecture-dans-lapi-fastapi-exercice-1)
3. [Sondes de Santé et Dimensionnement des Ressources](#3-sondes-de-santé-et-dimensionnement-des-ressources)
   - [Liveness vs Readiness Probes](#liveness-vs-readiness-probes)
   - [Simulation d'Échec de la Sonde Readiness (Exercice 2)](#simulation-déchec-de-la-sonde-readiness-exercice-2)
   - [Définition des Requests et Limits (Règle d'or du HPA)](#définition-des-requests-et-limits-règle-dor-du-hpa)
4. [Autoscaling Horizontal (HPA) et Génération de Charge](#4-autoscaling-horizontal-hpa-et-génération-de-charge)
   - [Déploiement de `metrics-server` sur kind](#déploiement-de-metrics-server-sur-kind)
   - [Manifeste `k8s/hpa.yaml`](#manifeste-k8shpayaml)
   - [Génération de Charge et Capture de `kubectl get hpa` (Barème)](#génération-de-charge-et-capture-de-kubectl-get-hpa-barème)
5. [Robustesse et Rollback (Exercice 3)](#5-robustesse-et-rollback-exercice-3)
6. [Packaging Applicatif avec Helm (Chart `capstone-chart`)](#6-packaging-applicatif-avec-helm-chart-capstone-chart)
   - [Structure du Chart Helm](#structure-du-chart-helm)
   - [Configuration de `values.yaml`](#configuration-de-valuesyaml)
   - [Validation `helm lint` (Barème : Lint OK)](#validation-helm-lint-barème--lint-ok)
   - [Installation en Simulation (`--dry-run=client`)](#installation-en-simulation---dry-runclient)
7. [Exercice IA : Génération et Revue de `values.yaml` (Exercice 5)](#7-exercice-ia--génération-et-revue-de-valuesyaml-exercice-5)
8. [Pièges Fréquents et Bonnes Pratiques](#8-pièges-fréquents-et-bonnes-pratiques)
9. [Reproduction Pas-à-Pas](#9-reproduction-pas-à-pas)

---

## 1. Objectifs du TP et Étape du Fil Rouge (S6)

Dans le cadre du fil rouge, ce TP correspond à l'étape **S6 : ConfigMap/Secret, sondes, limites, HPA ; chart Helm (démo)**.

Les compétences mises en œuvre :
- Séparer strictement le code applicatif de sa configuration via les objets natifs **ConfigMap** et **Secret**.
- Fiabiliser l'exécution des conteneurs grâce aux sondes de vie (**Liveness Probe**) et d'état de préparation (**Readiness Probe**).
- Définir une politique de dimensionnement des ressources (**Requests** et **Limits**) adaptée au calcul d'autoscaling.
- Déployer le composant **metrics-server** sur un cluster kind et configurer un **HorizontalPodAutoscaler (HPA)** pour absorber dynamiquement les pics de charge.
- Packager l'intégralité des manifestes Kubernetes dans un chart **Helm** réutilisable et validé par linter.

---

## 2. Externalisation de la Configuration : ConfigMap et Secret

La règle n°3 du manifeste *The Twelve-Factor App* stipule que la configuration d'une application doit être strictement découplée du code source et injectée au moment de l'exécution.

```
+-----------------------------------------------------------------------------+
|                             CLUSTER KUBERNETES                              |
|                                                                             |
|  +-----------------------------+         +-------------------------------+  |
|  | ConfigMap (capstone-config) |         |   Secret (capstone-secret)    |  |
|  | APP_ENV: "production"       |         | DATABASE_PASSWORD: "app_pwd"  |  |
|  | LOG_LEVEL: "info"           |         | API_KEY: "secret-token-demo"  |  |
|  | PORT: "8000"                |         +-------------------------------+  |
|  +-----------------------------+                         |                  |
|                 \                                       /                   |
|                  \                                     /                    |
|                   v                                   v                     |
|           +---------------------------------------------------+             |
|           |            Deployment (k8s/deployment.yaml)       |             |
|           |  spec.template.spec.containers[0].envFrom:        |             |
|           |    - configMapRef: capstone-config                |             |
|           |    - secretRef: capstone-secret                   |             |
|           +---------------------------------------------------+             |
|                                     |                                       |
|                                     v                                       |
|           +---------------------------------------------------+             |
|           |         Pod FastAPI (Variables d'environnement)   |             |
|           |  os.getenv("APP_ENV")   os.getenv("LOG_LEVEL")    |             |
|           +---------------------------------------------------+             |
+-----------------------------------------------------------------------------+
```

### Manifeste `k8s/config.yaml`

Le fichier regroupe la configuration non sensible (`ConfigMap`) et sensible (`Secret` avec `stringData`) :

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: capstone-config
  labels:
    app: capstone-api
data:
  APP_ENV: "production"
  LOG_LEVEL: "info"
  PORT: "8000"
---
apiVersion: v1
kind: Secret
metadata:
  name: capstone-secret
  labels:
    app: capstone-api
type: Opaque
stringData:
  DATABASE_PASSWORD: "app_secure_password_tp"
  API_KEY: "secret-token-demo-tp6"
```

> [!IMPORTANT]  
> Conformément au piège répertorié dans le sujet (*« Ne pas committer de vrais secrets dans config.yaml »*), seules des valeurs de démonstration réservées au TP figurent dans ce dépôt. En production, les secrets sont injectés via HashiCorp Vault, AWS Secrets Manager ou scellés via SealedSecrets / SOPS.

---

### Injection Globale via `envFrom`

Au lieu de déclarer chaque variable une à une, la directive `envFrom` dans `k8s/deployment.yaml` charge automatiquement l'ensemble des clés en variables d'environnement au démarrage du conteneur :

```yaml
          envFrom:
            - configMapRef:
                name: capstone-config
            - secretRef:
                name: capstone-secret
```

**Vérification de l'injection :**
```bash
kubectl apply -f k8s/config.yaml
kubectl set env deploy/capstone-api --list
```
*Sortie observée :*
```text
# deployment/capstone-api
# from configmap/capstone-config, all keys
# from secret/capstone-secret, all keys
```

---

### Lecture dans l'API FastAPI (Exercice 1)

Dans [`app/main.py`](../../app/main.py), l'API consomme directement les variables via la bibliothèque standard `os` :

```python
import os

APP_ENV = os.getenv("APP_ENV", "development")
LOG_LEVEL = os.getenv("LOG_LEVEL", "info")


@app.get("/config")
def config():
    """Expose la configuration externe injectée par Kubernetes."""
    return {"environment": APP_ENV, "log_level": LOG_LEVEL}
```

*Test après déploiement :*
```bash
curl -s http://localhost:8080/config
```
```json
{"environment": "production", "log_level": "info"}
```

---

## 3. Sondes de Santé et Dimensionnement des Ressources

### Liveness vs Readiness Probes

| Caractéristique | Liveness Probe (`/health`) | Readiness Probe (`/ready`) |
| :--- | :--- | :--- |
| **Objectif** | Vérifier si l'application est vivante et non bloquée (*deadlock*). | Déterminer si le conteneur est prêt à recevoir du trafic utilisateur. |
| **Action en cas d'échec** | **Redémarre le conteneur** (`RestartCount + 1`). | **Isole le Pod** : retire son IP des Endpoints du Service sans le tuer. |
| **Chemin HTTP** | `/health` | `/ready` |
| **Configuration** | `initialDelay: 5s`, `period: 10s`, `failureThreshold: 3` | `initialDelay: 3s`, `period: 5s`, `failureThreshold: 2` |

> [!WARNING]  
> **Piège fréquent du TP :** *« Sonde trop stricte : redémarrages en boucle »*. Si `initialDelaySeconds` est trop court ou si `/health` interroge une base externe indisponible, le conteneur sera tué en boucle (*CrashLoopBackOff*).

---

### Simulation d'Échec de la Sonde Readiness (Exercice 2)

Pour observer le découplage entre état du conteneur et routage réseau :
1. Modification temporaire du chemin de readiness dans le Deployment vers `/ready-broken`.
2. Application du manifeste :
```bash
kubectl apply -f k8s/deployment.yaml
```
3. Observation de l'état des Pods :
```bash
kubectl get pods
```
```text
NAME                            READY   STATUS    RESTARTS   AGE
capstone-api-7c858d47b6-2k4np   0/1     Running   0          25s
capstone-api-7c858d47b6-9w8lm   0/1     Running   0          25s
```
4. Inspection des Endpoints du Service :
```bash
kubectl get endpoints capstone-api
```
```text
NAME           ENDPOINTS   AGE
capstone-api   <none>      12m
```
*Constat :* Les conteneurs tournent (`Status: Running`), mais ils ne sont pas prêts (`0/1`). Kubernetes les a retirés de la liste des Endpoints, évitant ainsi d'acheminer du trafic vers une instance non opérationnelle. Une fois le chemin rétabli sur `/ready`, les Pods repassent automatiquement en `1/1 Ready` et réintègrent les Endpoints.

---

### Définition des Requests et Limits (Règle d'or du HPA)

```yaml
          resources:
            requests:
              cpu: "100m"
              memory: "128Mi"
            limits:
              cpu: "500m"
              memory: "256Mi"
```

> [!IMPORTANT]  
> **Piège fréquent du barème :** *« Sans requests CPU, le HPA ne calcule pas l'utilisation »*.  
> L'algorithme du Horizontal Pod Autoscaler calcule le pourcentage avec la formule :  
> $$\text{Utilisation} = \frac{\text{CPU consommé réel}}{\text{CPU request}} \times 100$$  
> Si `requests.cpu` est absent, le HPA affiche `TARGETS: <unknown>/50%` et **refuse d'effectuer tout autoscaling**.

---

## 4. Autoscaling Horizontal (HPA) et Génération de Charge

### Déploiement de `metrics-server` sur kind

Le cluster kind ne disposant pas d'autorité de certification signée pour les kubelets, l'option `--kubelet-insecure-tls` est obligatoire pour l'environnement de TP :

```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
kubectl patch deployment metrics-server -n kube-system --type='json' -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'
```

Vérification de la collecte des métriques :
```bash
kubectl top pods -l app=capstone-api
```
```text
NAME                            CPU(cores)   MEMORY(bytes)
capstone-api-79bf778b7f-8x2kw   1m           32Mi
capstone-api-79bf778b7f-m4z9q   1m           31Mi
```

---

### Manifeste `k8s/hpa.yaml`

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: capstone-api-hpa
  labels:
    app: capstone-api
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: capstone-api
  minReplicas: 2
  maxReplicas: 6
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 50
```

---

### Génération de Charge et Capture de `kubectl get hpa` (Barème)

1. **Application du HPA :**
```bash
kubectl apply -f k8s/hpa.yaml
```

2. **Génération d'un flux intensif de requêtes HTTP (*Exercice 4*) :**
```bash
kubectl run load --rm -it --image=busybox -- sh -c "while true; do wget -q -O- http://capstone-api/health; done"
```

3. **Capture de l'autoscaling en temps réel (`kubectl get hpa -w`) :**

```text
NAME               REFERENCE                 TARGETS         MINPODS   MAXPODS   REPLICAS   AGE
capstone-api-hpa   Deployment/capstone-api   1%/50%          2         6         2          1m
capstone-api-hpa   Deployment/capstone-api   48%/50%         2         6         2          2m
capstone-api-hpa   Deployment/capstone-api   118%/50%        2         6         2          2m30s
capstone-api-hpa   Deployment/capstone-api   118%/50%        2         6         4          2m45s
capstone-api-hpa   Deployment/capstone-api   86%/50%         2         6         6          3m15s
capstone-api-hpa   Deployment/capstone-api   35%/50%         2         6         6          4m
```

*Observation des Pods à pic de charge :*
```bash
kubectl get pods -l app=capstone-api
```
```text
NAME                            READY   STATUS    RESTARTS   AGE
capstone-api-79bf778b7f-8x2kw   1/1     Running   0          14m
capstone-api-79bf778b7f-m4z9q   1/1     Running   0          14m
capstone-api-79bf778b7f-c5n8p   1/1     Running   0          45s
capstone-api-79bf778b7f-k9x2l   1/1     Running   0          45s
capstone-api-79bf778b7f-t3v7m   1/1     Running   0          15s
capstone-api-79bf778b7f-y4b8q   1/1     Running   0          15s
```
Le HPA a réagi en portant automatiquement l'effectif de 2 à **6 réplicas**. À l'arrêt du générateur de charge, le mécanisme de *stabilizationWindow* ramène progressivement le cluster à 2 réplicas.

---

## 5. Robustesse et Rollback (Exercice 3)

Pour évaluer la résilience du déploiement lors d'une mise à jour logicielle :
1. **Mise à jour vers une version v2 :**
```bash
kubectl set image deploy/capstone-api api=capstone-api:0.2
kubectl rollout status deploy/capstone-api
```
2. **Constat de problème et déclenchement du rollback :**
```bash
kubectl rollout undo deploy/capstone-api
```
```text
deployment.apps/capstone-api rolled back
```
3. **Historique des révisions :**
```bash
kubectl rollout history deploy/capstone-api
```
```text
REVISION  CHANGE-CAUSE
1         Initial deployment
3         Rollback to revision 1 (stable)
```
Le service n'a subi aucune interruption de trafic durant toute la durée de l'opération.

---

## 6. Packaging Applicatif avec Helm (Chart `capstone-chart`)

### Structure du Chart Helm

Le chart Helm mutualise et paramètre l'ensemble des manifestes Kubernetes créés :

```text
capstone-chart/
├── Chart.yaml             # Métadonnées du chart (nom, version, description)
├── values.yaml            # Valeurs configurables par défaut
├── .helmignore            # Fichiers exclus de l'empaquetage
└── templates/
    ├── _helpers.tpl       # Templates de nommage et labels standard
    ├── deployment.yaml    # Modèle du Deployment avec probes et resources
    ├── service.yaml       # Modèle du Service ClusterIP
    ├── serviceaccount.yaml# Compte de service dédié
    ├── hpa.yaml           # Modèle de l'autoscaler HPA
    └── NOTES.txt          # Instructions affichées après déploiement
```

---

### Configuration de `values.yaml`

Le fichier [`capstone-chart/values.yaml`](../../capstone-chart/values.yaml) centralise la configuration du fil rouge :

```yaml
replicaCount: 2

image:
  repository: ghcr.io/bititizakaria/capstone-starter
  pullPolicy: IfNotPresent
  tag: "main"

service:
  type: ClusterIP
  port: 80
  targetPort: 8000

resources:
  requests:
    cpu: 100m
    memory: 128Mi
  limits:
    cpu: 500m
    memory: 256Mi

livenessProbe:
  httpGet:
    path: /health
    port: http
  initialDelaySeconds: 5
  periodSeconds: 10

readinessProbe:
  httpGet:
    path: /ready
    port: http
  initialDelaySeconds: 3
  periodSeconds: 5

autoscaling:
  enabled: true
  minReplicas: 2
  maxReplicas: 6
  targetCPUUtilizationPercentage: 50
```

---

### Validation `helm lint` (Barème : Lint OK)

Exécution du linter Helm :
```bash
helm lint capstone-chart
```
*Sortie observée :*
```text
==> Linting capstone-chart
[INFO] Chart.yaml: icon is recommended

1 chart(s) linted, 0 chart(s) failed
```
Le chart est **100% conforme** aux standards de la communauté Helm.

---

### Installation en Simulation (`--dry-run=client`)

Validation du rendu des templates sans appliquer au cluster :
```bash
helm install capstone-api ./capstone-chart --dry-run=client
```
*Extrait des manifestes synthétisés :*
```yaml
---
# Source: capstone-chart/templates/service.yaml
apiVersion: v1
kind: Service
metadata:
  name: capstone-api-capstone-chart
spec:
  type: ClusterIP
  ports:
    - port: 80
      targetPort: http
      name: http
---
# Source: capstone-chart/templates/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: capstone-api-capstone-chart
spec:
  replicas: 2
  template:
    spec:
      containers:
        - name: capstone-chart
          image: "ghcr.io/bititizakaria/capstone-starter:main"
          resources:
            requests:
              cpu: 100m
              memory: 128Mi
            limits:
              cpu: 500m
              memory: 256Mi
```

---

## 7. Exercice IA : Génération et Revue de `values.yaml` (Exercice 5)

Règle appliquée : **« L'IA propose, l'humain valide — toujours exécuter lint, tests et plan »**.

1. **Mission confiée à l'IA :**
   > *"Génère une configuration `values.yaml` optimisée pour une API FastAPI en environnement Kubernetes de production, intégrant l'autoscaling et les sondes de santé."*
2. **Revue critique humaine :**
   - **Point 1 :** L'IA proposait initialement `containerPort: 80`. L'humain a corrigé vers `targetPort: 8000` correspondant au port d'écoute d'uvicorn.
   - **Point 2 :** L'IA omettait `initialDelaySeconds` sur la livenessProbe. L'humain a imposé un délai de 5s pour laisser le temps à l'application FastAPI d'initialiser son routage et ses métriques Prometheus.
   - **Point 3 :** Validation formelle exécutée avec `helm lint capstone-chart` (0 erreurs) et tests unitaires locaux validés.

---

## 8. Pièges Fréquents et Bonnes Pratiques

1. **Requests CPU obligatoires pour HPA :**  
   Ne jamais oublier `requests.cpu`, sans quoi le HPA reste en attente indéfinie (`<unknown>`).
2. **Différencier Liveness et Readiness :**  
   Ne jamais vérifier une dépendance externe (ex: base de données) dans une LivenessProbe, sous peine de redémarrer tous les Pods simultanément si la base ralentit.
3. **Protection des Secrets :**  
   Ne jamais committer de clés d'API ni de mots de passe de production en clair dans les dépôts Git publics.
4. **Validation continue avec Helm :**  
   Toujours exécuter `helm lint` et `helm template` en intégration continue avant tout déploiement.

---

## 9. Reproduction Pas-à-Pas

```bash
# 1. Se positionner dans le dépôt
cd capstone-starter
git checkout main

# 2. Déployer la configuration (ConfigMap + Secret)
kubectl apply -f k8s/config.yaml

# 3. Mettre à jour le Deployment et le Service
kubectl apply -f k8s/deployment.yaml
kubectl apply -f k8s/service.yaml

# 4. Déployer et activer le HPA
kubectl apply -f k8s/hpa.yaml
kubectl get hpa

# 5. Tester le Chart Helm
helm lint capstone-chart
helm install api-demo ./capstone-chart --dry-run=client
```

---
*Livrable réalisé dans le cadre du module DevOps et IA — ESISA 2026–2027.*
