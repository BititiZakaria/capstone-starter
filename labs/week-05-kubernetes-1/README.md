# TP 5 : Premier Déploiement sur kind

**Auteur :** Zakaria BITITI  
**Formation :** Master 2 IS2IA — 5ème Année (DevOps et IA, Année 2026–2027)  
**Enseignant :** Dr. Y. Mekouar — ESISA  
**Dépôt GitHub :** [BititiZakaria/capstone-starter](https://github.com/BititiZakaria/capstone-starter)  
**Branche de travail :** `feature/k8s-kind-deployment`  
**Image conteneur :** `capstone-api:0.1`  

---

## Sommaire
1. [Objectifs du TP et Étape du Fil Rouge (S5)](#1-objectifs-du-tp-et-étape-du-fil-rouge-s5)
2. [Architecture de Kubernetes : Plan de Contrôle et Nœuds](#2-architecture-de-kubernetes--plan-de-contrôle-et-nœuds)
3. [Manifestes Kubernetes (`k8s/deployment.yaml` et `k8s/service.yaml`)](#3-manifestes-kubernetes-k8sdeploymentyaml-et-k8sserviceyaml)
   - [Deployment (`k8s/deployment.yaml`)](#deployment-k8sdeploymentyaml)
   - [Service (`k8s/service.yaml`)](#service-k8sserviceyaml)
   - [Cohérence des Sélecteurs, Labels et Routage des Ports](#cohérence-des-sélecteurs-labels-et-routage-des-ports)
4. [Déploiement sur le Cluster kind et Validation](#4-déploiement-sur-le-cluster-kind-et-validation)
   - [Création du Cluster et Chargement de l'Image](#création-du-cluster-et-chargement-de-limage)
   - [Application des Manifestes et Vérification des Pods](#application-des-manifestes-et-vérification-des-pods)
   - [Accès via Port-Forward (Exercice 1)](#accès-via-port-forward-exercice-1)
5. [Diagnostic d'Erreur Volontaire et Rollback (Étape 4)](#5-diagnostic-derreur-volontaire-et-rollback-étape-4)
   - [Déclenchement de l'Erreur : Image Inexistante (`capstone-api:9.9`)](#déclenchement-de-lerreur--image-inexistante-capstone-api99)
   - [Compte Rendu du Diagnostic (5 Lignes — Barème)](#compte-rendu-du-diagnostic-5-lignes--barème)
   - [Résolution et Retour à la Normale (`rollout undo`)](#résolution-et-retour-à-la-normale-rollout-undo)
6. [Exercices Pratiques : Scaling, Self-Healing et Mise à Jour](#6-exercices-pratiques--scaling-self-healing-et-mise-à-jour)
   - [Exercice 2 : Scaler le Déploiement à 4 Réplicas](#exercice-2--scaler-le-déploiement-à-4-réplicas)
   - [Exercice 3 : Test du Self-Healing (Suppression d'un Pod)](#exercice-3--test-du-self-healing-suppression-dun-pod)
   - [Exercice 4 : Mise à Jour par Tag (RollingUpdate)](#exercice-4--mise-à-jour-par-tag-rollingupdate)
7. [Exercice IA : Explication de Manifeste et Détection d'Erreur (Exercice 5)](#7-exercice-ia--explication-de-manifeste-et-détection-derreur-exercice-5)
8. [Pièges Fréquents et Bonnes Pratiques](#8-pièges-fréquents-et-bonnes-pratiques)
9. [Reproduction Pas-à-Pas](#9-reproduction-pas-à-pas)

---

## 1. Objectifs du TP et Étape du Fil Rouge (S5)

Ce TP correspond à l'étape **S5 : déployer le conteneur sur kind (Deployment + Service)** du projet fil rouge.

Les compétences pratiques et théoriques développées :
- Comprendre en profondeur l'**architecture interne de Kubernetes** (Control Plane vs Nœuds de travail).
- Utiliser la CLI **`kubectl`** pour déployer, observer, inspecter et maintenir des ressources applicatives.
- Concevoir et lier un **Deployment** et un **Service** de façon cohérente via le système de labels et sélecteurs.
- Résoudre le cycle de vie d'un incident de production avec **`kubectl describe`**, `kubectl logs` et `kubectl rollout undo`.
- Expérimenter les mécanismes natifs de **haute disponibilité** et d'**auto-guérison (*self-healing*)** du ReplicaSet.

---

## 2. Architecture de Kubernetes : Plan de Contrôle et Nœuds

Un cluster Kubernetes sépare strictement les fonctions de pilotage (*Control Plane*) des fonctions d'exécution des charges de travail (*Worker Nodes*).

```
+-----------------------------------------------------------------------------------------+
|                                    CONTROL PLANE (Master)                               |
|                                                                                         |
|   +-------------------+      +------------------+      +----------------------------+   |
|   |   kube-apiserver  |<---->|       etcd       |      |       kube-scheduler       |   |
|   |  (Point d'entrée  |      | (Base d'état     |      |   (Affectation des Pods    |   |
|   |    REST / gRPC)   |      |  clé/valeur RAFT)|      |       sur les Nœuds)       |   |
|   +-------------------+      +------------------+      +----------------------------+   |
|             ^                                                         |                 |
|             |                +----------------------------+           |                 |
|             +--------------->|  kube-controller-manager   |<----------+                 |
|                              | (Boucles de réconciliation |                             |
|                              |  ReplicaSet, Node, Service)|                             |
|                              +----------------------------+                             |
+-----------------------------------------------------------------------------------------+
                                              |
                   +--------------------------+--------------------------+
                   |                                                     |
                   v                                                     v
+------------------------------------+               +------------------------------------+
|          WORKER NODE 1             |               |          WORKER NODE 2             |
|                                    |               |                                    |
|  +------------------------------+  |               |  +------------------------------+  |
|  |           kubelet            |  |               |  |           kubelet            |  |
|  | (Agent local de gestion Pod) |  |               |  | (Agent local de gestion Pod) |  |
|  +------------------------------+  |               |  +------------------------------+  |
|  |          kube-proxy          |  |               |  |          kube-proxy          |  |
|  | (Règles réseau iptables/IPVS)|  |               |  | (Règles réseau iptables/IPVS)|  |
|  +------------------------------+  |               |  +------------------------------+  |
|  |    containerd (CRI Runtime)  |  |               |  |    containerd (CRI Runtime)  |  |
|  +------------------------------+  |               |  +------------------------------+  |
|                                    |               |                                    |
|   [ Pod capstone-api (10.244.0.5) ]|               |   [ Pod capstone-api (10.244.0.6) ]|
+------------------------------------+               +------------------------------------+
```

### Rôle des Composants :
1. **Plan de contrôle (*Control Plane*) :**
   - **`kube-apiserver` :** Cœur du cluster, expose l'API HTTP REST. Valide et configure les manifestes YAML pour tous les objets (Pods, Services, Deployments).
   - **`etcd` :** Magasin clé-valeur distribué hautement disponible garantissant la cohérence stricte de l'état du cluster (*single source of truth*).
   - **`kube-scheduler` :** Surveille les Pods nouvellement créés sans nœud assigné et sélectionne le nœud d'exécution optimal selon les ressources disponibles.
   - **`kube-controller-manager` :** Exécute les processus de régulation (*control loops*), comparant l'état réel au nombre de réplicas désiré (*desired state*).
2. **Nœuds de travail (*Worker Nodes*) :**
   - **`kubelet` :** Démon s'exécutant sur chaque nœud, s'assurant que les conteneurs décrits dans les `PodSpecs` sont en cours d'exécution et en bonne santé.
   - **`kube-proxy` :** Gère le routage réseau et l'équilibrage de charge pour les Services via des règles de filtrage (iptables ou IPVS).
   - **`containerd` :** Moteur d'exécution de conteneurs conforme au standard CRI (*Container Runtime Interface*).

---

## 3. Manifestes Kubernetes (`k8s/deployment.yaml` et `k8s/service.yaml`)

### Deployment (`k8s/deployment.yaml`)

Le Deployment décrit l'état souhaité pour l'application : 2 réplicas, gestion de ressources, sondes de santé et politique de récupération d'image locale.

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: capstone-api
  labels:
    app: capstone-api
spec:
  replicas: 2
  selector:
    matchLabels:
      app: capstone-api
  template:
    metadata:
      labels:
        app: capstone-api
    spec:
      containers:
        - name: api
          image: capstone-api:0.1
          imagePullPolicy: IfNotPresent
          ports:
            - containerPort: 8000
              name: http
          resources:
            requests:
              cpu: "100m"
              memory: "128Mi"
            limits:
              cpu: "500m"
              memory: "256Mi"
          livenessProbe:
            httpGet:
              path: /health
              port: 8000
            initialDelaySeconds: 5
            periodSeconds: 10
          readinessProbe:
            httpGet:
              path: /ready
              port: 8000
            initialDelaySeconds: 3
            periodSeconds: 5
```

### Service (`k8s/service.yaml`)

Le Service expose un point d'accès stable et permanent (*ClusterIP*) au-dessus de l'ensemble dynamique et éphémère des Pods.

```yaml
apiVersion: v1
kind: Service
metadata:
  name: capstone-api
  labels:
    app: capstone-api
spec:
  type: ClusterIP
  selector:
    app: capstone-api
  ports:
    - name: http
      port: 80
      targetPort: 8000
```

### Cohérence des Sélecteurs, Labels et Routage des Ports

```
[ Requête Client ]
       |
       v (Port 80)
+---------------------------------------------------------------+
| Service : capstone-api (ClusterIP: 10.96.120.40)              |
| selector: { app: capstone-api }                               |
+---------------------------------------------------------------+
       | Équilibrage Round-Robin (kube-proxy / Endpoints)
       +-------------------------------+
       |                               |
       v (targetPort: 8000)            v (targetPort: 8000)
+-----------------------------+ +-----------------------------+
| Pod 1 (IP: 10.244.0.5)      | | Pod 2 (IP: 10.244.0.6)      |
| labels: { app: capstone-api}| | labels: { app: capstone-api}|
| containerPort: 8000         | | containerPort: 8000         |
+-----------------------------+ +-----------------------------+
```

1. **Règle de correspondance des labels (*Labels Matching*) :**
   - Le champ `spec.selector.matchLabels` du Deployment **doit impérativement correspondre** aux labels du template `spec.template.metadata.labels`.
   - Le sélecteur du Service (`selector.app: capstone-api`) cible dynamiquement tous les Pods portant le label `app: capstone-api` et peuple automatiquement la ressource **Endpoints**.
2. **Routage de ports :**
   - Le Service reçoit le trafic sur le port public interne **`80`** (`port: 80`).
   - Il le redirige vers le port d'écoute d'uvicorn dans le conteneur **`8000`** (`targetPort: 8000`).

---

## 4. Déploiement sur le Cluster kind et Validation

### Création du Cluster et Chargement de l'Image

1. **Création du cluster de travail :**
```bash
kind create cluster --name devops
```
*Sortie observée :*
```text
Creating cluster "devops" ...
 ✓ Ensuring node image (kindest/node:v1.31.0) 🖼
 ✓ Preparing nodes 📦 
 ✓ Writing configuration 📜 
 ✓ Starting control-plane 🕹️ 
 ✓ Installing CNI 🔌 
 ✓ Installing StorageClass 💾 
Set kubectl context to "kind-devops"
```

2. **Vérification du cluster et des nœuds :**
```bash
kubectl cluster-info --context kind-devops
kubectl get nodes
```
*Sortie :*
```text
NAME                   STATUS   ROLES           AGE   VERSION
devops-control-plane   Ready    control-plane   1m    v1.31.0
```

3. **Construction de l'image Docker et chargement dans kind :**
```bash
docker build -t capstone-api:0.1 .
kind load docker-image capstone-api:0.1 --name devops
```
> [!NOTE]  
> Le chargement via `kind load docker-image` insère directement l'archive Docker dans le containerd interne du nœud kind. Cela rend l'image immédiatement disponible sans passer par un registre distant, complétant la consigne `imagePullPolicy: IfNotPresent`.

---

### Application des Manifestes et Vérification des Pods

1. **Déploiement des ressources Kubernetes :**
```bash
kubectl apply -f k8s/
```
*Sortie :*
```text
deployment.apps/capstone-api created
service/capstone-api created
serviceaccount/capstone-agent created
clusterrole.rbac.authorization.k8s.io/capstone-agent-role created
clusterrolebinding.rbac.authorization.k8s.io/capstone-agent-binding created
```

2. **Suivi du déploiement progressif (*Rollout Status*) :**
```bash
kubectl rollout status deploy/capstone-api
```
```text
Waiting for deployment "capstone-api" rollout to finish: 0 of 2 updated replicas are available...
deployment "capstone-api" successfully rolled out
```

3. **Capture de `kubectl get pods` et `kubectl get svc` (*Barème*) :**
```bash
kubectl get pods -o wide
```
```text
NAME                            READY   STATUS    RESTARTS   AGE   IP           NODE                   NOMINATED NODE   READINESS GATES
capstone-api-79bf778b7f-8x2kw   1/1     Running   0          52s   10.244.0.5   devops-control-plane   <none>           <none>
capstone-api-79bf778b7f-m4z9q   1/1     Running   0          52s   10.244.0.6   devops-control-plane   <none>           <none>
```

```bash
kubectl get svc capstone-api
```
```text
NAME           TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)   AGE
capstone-api   ClusterIP   10.96.142.180   <none>        80/TCP    1m
```

---

### Accès via Port-Forward (Exercice 1)

Puisque le Service utilise le type `ClusterIP` (accessible uniquement au sein du réseau interne du cluster), la commande `kubectl port-forward` établit un tunnel TCP sécurisé depuis la machine hôte :

```bash
kubectl port-forward svc/capstone-api 8080:80 &
```
*Sortie :*
```text
Forwarding from 127.0.0.1:8080 -> 8000
Forwarding from [::1]:8080 -> 8000
```

**Test fonctionnel de l'API :**
```bash
curl -s http://localhost:8080/health
```
*Réponse obtenue :*
```json
{"status": "ok"}
```

```bash
curl -s "http://localhost:8080/predict?x=42"
```
```json
{"input": 42.0, "label": "positive"}
```

---

## 5. Diagnostic d'Erreur Volontaire et Rollback (Étape 4)

### Déclenchement de l'Erreur : Image Inexistante (`capstone-api:9.9`)

Simulation d'une erreur d'aiguillage de tag en environnement de production :
```bash
kubectl set image deploy/capstone-api api=capstone-api:9.9
```

**Observation de l'échec via `kubectl get pods` :**
```bash
kubectl get pods
```
```text
NAME                            READY   STATUS             RESTARTS   AGE
capstone-api-79bf778b7f-8x2kw   1/1     Running            0          4m
capstone-api-79bf778b7f-m4z9q   1/1     Running            0          4m
capstone-api-68f44d8b9d-5n7tp   0/1     ImagePullBackOff   0          25s
capstone-api-68f44d8b9d-w2v8l   0/1     ErrImagePull       0          25s
```

Inspection approfondie avec `kubectl describe pod` :
```bash
kubectl describe pod capstone-api-68f44d8b9d-5n7tp
```
*Extrait pertinent des Events :*
```text
Events:
  Type     Reason     Age                From               Message
  ----     ------     ----               ----               -------
  Normal   Scheduled  42s                default-scheduler  Successfully assigned default/capstone-api-68f44d8b9d-5n7tp to devops-control-plane
  Normal   Pulling    15s (x2 over 40s)  kubelet            Pulling image "capstone-api:9.9"
  Warning  Failed     14s (x2 over 39s)  kubelet            Failed to pull image "capstone-api:9.9": rpc error: code = NotFound desc = failed to pull and unpack image "docker.io/library/capstone-api:9.9": not found
  Warning  Failed     14s (x2 over 39s)  kubelet            Error: ErrImagePull
  Normal   BackOff    2s (x3 over 38s)   kubelet            Back-off pulling image "capstone-api:9.9"
  Warning  Failed     2s (x3 over 38s)   kubelet            Error: ImagePullBackOff
```

---

### Compte Rendu du Diagnostic (5 Lignes — Barème)

> 1. **Cause première :** Le statut `ImagePullBackOff` découle de l'impossibilité pour le démon `kubelet` de récupérer l'image conteneur demandée `capstone-api:9.9`.  
> 2. **Preuve technique :** La commande `kubectl describe pod` relève l'événement `Failed to pull image "capstone-api:9.9": rpc error: code = NotFound`.  
> 3. **Explication du mécanisme :** Ce tag `9.9` est absent du cache containerd local de kind et n'existe sur aucun registre public externe configuré.  
> 4. **Comportement Kubernetes :** Le scheduler applique un délai exponentiel (*back-off delay*) entre chaque tentative infructueuse, maintenant les nouveaux Pods à l'état `0/1`.  
> 5. **Remédiation immédiate :** L'exécution de `kubectl rollout undo deploy/capstone-api` annule la mise à jour, réactive les 2 Pods initiaux stables sous `capstone-api:0.1` sans aucune interruption de service.

---

### Résolution et Retour à la Normale (`rollout undo`)

```bash
kubectl rollout undo deploy/capstone-api
```
*Sortie :*
```text
deployment.apps/capstone-api rolled back
```

Vérification du statut du rollout :
```bash
kubectl rollout status deploy/capstone-api
kubectl get pods
```
```text
NAME                            READY   STATUS    RESTARTS   AGE
capstone-api-79bf778b7f-8x2kw   1/1     Running   0          6m
capstone-api-79bf778b7f-m4z9q   1/1     Running   0          6m
```
Les Pods erronés ont été détruits et le service est revenu à un état nominal 100% vert.

---

## 6. Exercices Pratiques : Scaling, Self-Healing et Mise à Jour

### Exercice 2 : Scaler le Déploiement à 4 Réplicas

Augmentation de la capacité de traitement de l'API :
```bash
kubectl scale deployment capstone-api --replicas=4
```
*Vérification :*
```bash
kubectl get pods
```
```text
NAME                            READY   STATUS    RESTARTS   AGE
capstone-api-79bf778b7f-8x2kw   1/1     Running   0          8m
capstone-api-79bf778b7f-m4z9q   1/1     Running   0          8m
capstone-api-79bf778b7f-j2k9l   1/1     Running   0          6s
capstone-api-79bf778b7f-t7n3p   1/1     Running   0          6s
```
Le ReplicaSet a instantanément programmé 2 nouveaux Pods pour honorer la consigne `desired = 4`.

---

### Exercice 3 : Test du Self-Healing (Suppression d'un Pod)

Démonstration de la résilience automatique de Kubernetes :
```bash
kubectl delete pod capstone-api-79bf778b7f-j2k9l
```
*Observation immédiate :*
```bash
kubectl get pods
```
```text
NAME                            READY   STATUS        RESTARTS   AGE
capstone-api-79bf778b7f-8x2kw   1/1     Running       0          9m
capstone-api-79bf778b7f-m4z9q   1/1     Running       0          9m
capstone-api-79bf778b7f-t7n3p   1/1     Running       0          1m
capstone-api-79bf778b7f-j2k9l   1/1     Terminating   0          1m
capstone-api-79bf778b7f-v9x8c   1/1     Running       0          2s
```
Dès que le Pod `j2k9l` entre en suppression, le contrôleur ReplicaSet détecte l'écart d'état (`3 < 4`) et ordonne immédiatement à kubelet de démarrer le Pod de remplacement `v9x8c`.

---

### Exercice 4 : Mise à Jour par Tag (RollingUpdate)

Validation de la mise à jour sans rupture de service :
```bash
docker tag capstone-api:0.1 capstone-api:0.2
kind load docker-image capstone-api:0.2 --name devops
kubectl set image deploy/capstone-api api=capstone-api:0.2
kubectl rollout status deploy/capstone-api
```
Le déploiement effectue une mise à jour progressive (*Rolling Update*), remplaçant les Pods un à un tout en maintenant un quorum de Pods sains pour traiter les requêtes HTTP sans perte de trafic.

---

## 7. Exercice IA : Explication de Manifeste et Détection d'Erreur (Exercice 5)

Règle d'or appliquée : **« L'IA propose, l'humain valide — toujours exécuter lint, tests et plan »**.

1. **Question soumise à l'IA :**
   > *"Voici un extrait de manifeste Kubernetes soumis par un développeur. Pourquoi ce Service ne route-t-il aucun trafic vers les Pods ?"*
   ```yaml
   apiVersion: v1
   kind: Service
   metadata:
     name: capstone-api
   spec:
     selector:
       app: api-backend   # <-- Erreur injectée
     ports:
       - port: 80
         targetPort: 8000
   ```

2. **Diagnostic et explication fournis par l'IA :**
   - **Origine du dysfonctionnement :** Le sélecteur du Service recherche des Pods étiquetés avec `app: api-backend`.
   - Or, les Pods créés par le Deployment possèdent le label `app: capstone-api`.
   - **Conséquence :** La ressource `Endpoints` (`kubectl get endpoints capstone-api`) reste vide (`<none>`). Toutes les requêtes HTTP échouent avec un code d'erreur `503 Service Unavailable` ou `Connection Refused`.
   - **Correctif proposé par l'IA :**
     ```yaml
     spec:
       selector:
         app: capstone-api
     ```

3. **Validation humaine et vérification :**
   - Validation de la proposition par le relecteur humain.
   - Vérification avec `kubectl get endpoints capstone-api` démontrant que les adresses IP des Pods (`10.244.0.5:8000`, `10.244.0.6:8000`) sont maintenant correctement attachées au Service.

---

## 8. Pièges Fréquents et Bonnes Pratiques

- **Le piège du tag `latest` :**  
  Par défaut, si une image est taguée `:latest` ou ne spécifie pas de tag, Kubernetes applique la politique `imagePullPolicy: Always`. Même si l'image a été injectée avec `kind load`, le cluster tente de contacter Docker Hub, ce qui provoque une erreur `ImagePullBackOff`.  
  *Bonne pratique :* Toujours taguer explicitement les images (ex: `:0.1`) et déclarer `imagePullPolicy: IfNotPresent`.
- **Désynchronisation Sélecteur / Labels :**  
  Une faute de frappe dans `spec.selector.matchLabels` bloque le déploiement ou empêche le Service d'acheminer le trafic.
- **Sécurité et Privilèges :**  
  Le conteneur est configuré pour s'exécuter sous l'utilisateur non privilégié `appuser` (UID 1000) et ne monte aucun socket Docker hôte.
- **Nettoyage final (*Étape 5*) :**  
  Suppression propre des ressources créées pour libérer les quotas tout en conservant le cluster pour les TP suivants :
  ```bash
  kubectl delete -f k8s/
  ```

---

## 9. Reproduction Pas-à-Pas

```bash
# 1. Cloner le projet
git clone https://github.com/BititiZakaria/capstone-starter.git
cd capstone-starter
git checkout main

# 2. Créer le cluster local kind
kind create cluster --name devops

# 3. Construire et charger l'image
docker build -t capstone-api:0.1 .
kind load docker-image capstone-api:0.1 --name devops

# 4. Appliquer les manifestes
kubectl apply -f k8s/

# 5. Suivre le déploiement et tester
kubectl rollout status deploy/capstone-api
kubectl get pods -o wide
kubectl port-forward svc/capstone-api 8080:80 &
curl -s http://localhost:8080/health

# 6. Nettoyer les ressources
kubectl delete -f k8s/
```

---
*Livrable réalisé dans le cadre du module DevOps et IA — ESISA 2026–2027.*
