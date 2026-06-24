# Rapport de deploiement K3s sur vSphere

Date : 2026-06-24

Projet : DockerELK_v2
Environnement : laboratoire vSphere, valeurs anonymisees

## Objectif

Provisionner avec Terraform un cluster K3s compose de trois VMs Ubuntu 22.04,
puis installer Argo CD comme socle GitOps :

| Noeud | Role | Capacite |
| --- | --- | --- |
| `k3s-server-1` | Control-plane | 2 vCPU, 4 Go RAM, disque thin 30 Go |
| `k3s-agent-1` | Worker | 2 vCPU, 4 Go RAM, disque thin 30 Go |
| `k3s-agent-2` | Worker | 2 vCPU, 4 Go RAM, disque thin 30 Go |

Le deploiement des workloads ELK n'entre pas dans cette execution. La stack
Elastic 6.x doit d'abord etre migree vers une version supportee et son stockage
Kubernetes doit etre defini.

## Extension Elastic Stack

Le cluster a ensuite recu un profil Elastic moderne orchestre par ECK :

| Composant | Version | Placement | Exposition |
| --- | --- | --- | --- |
| ECK | `3.4.0` | `elastic-system` | Interne |
| Elasticsearch | `9.4.2` | Worker 1 | Interne, TLS |
| Kibana | `9.4.2` | Worker 2 | NodePort `30601`, TLS |
| Logstash | `9.4.2` | Control-plane | NodePort `30514`, TCP JSON |

Elasticsearch utilise un PVC `local-path` de `15 Gi`. Ce choix convient au
laboratoire mais ne replique pas les donnees entre les noeuds.

L'orchestrateur execute sept phases :

1. controle des trois noeuds et de la StorageClass ;
2. installation idempotente de l'operateur ECK ;
3. application server-side des manifests Kustomize ;
4. attente d'Elasticsearch vert et de la generation observee ;
5. attente de Kibana vert et de la generation observee ;
6. attente de Logstash et de la generation observee ;
7. envoi d'un evenement, recherche dans Elasticsearch et controle Kibana.

Commande :

```powershell
powershell -ExecutionPolicy Bypass -File `
  infra\k3s-vsphere\scripts\Deploy-ElasticStack.ps1
```

Incidents rencontres pendant cette extension :

- les formes courtes `kubectl -o` entraient en conflit avec les parametres
  communs PowerShell ; elles ont ete remplacees par `--output=...` ;
- les listes de ressources separees par des virgules etaient eclatees par
  PowerShell ; elles sont maintenant transmises comme une chaine unique ;
- l'utilisateur Logstash gere par ECK refusait la creation d'un index hors du
  prefixe autorise ; l'index cible est devenu
  `logstash-dockerelk-infra-*` ;
- un evenement refuse restait en retry et retardait le rechargement du
  pipeline ; le pod Logstash a ete redemarre apres correction ;
- la premiere verification passait un corps JSON a `curl.exe`, fragile sous
  Windows PowerShell ; elle utilise maintenant une query URI encodee.

Etat final valide :

```text
Elasticsearch  green  1/1
Kibana         green  1/1
Logstash       green  1/1
PVC ES         Bound  15Gi
Test ingestion indexe
Kibana         available
```

La gestion Argo CD ne doit etre activee qu'apres publication de
`kubernetes/overlays/lab-k3s` dans le depot distant. Le script
`Register-ElasticGitOps.ps1` controle cette publication avant de creer
l'application.

## Donnees et dashboard Kibana

Le script `Seed-ElasticDemo.ps1` injecte par defaut `240` evenements JSON via
le NodePort Logstash. Les evenements representent une journee d'activite sur
six hotes fictifs :

```text
web-01, web-02, api-01, db-01, queue-01, k3s-worker-01
```

Chaque document contient :

- `@timestamp` ;
- `event.id`, `event.category`, `event.severity`, `event.outcome` ;
- `host.name`, `host.role` ;
- `service.name` ;
- CPU, memoire, disque et temps de reponse.

Le script cree de facon idempotente :

| Objet | Identifiant |
| --- | --- |
| Data view | `dockerelk-infra` |
| Compteur | `dockerelk-events-total` |
| Courbe CPU | `dockerelk-cpu-over-time` |
| Histogramme severite | `dockerelk-severity` |
| Dashboard | `dockerelk-infra-overview` |

Execution autonome :

```powershell
powershell -ExecutionPolicy Bypass -File `
  infra\k3s-vsphere\scripts\Seed-ElasticDemo.ps1
```

L'orchestrateur `Deploy-ElasticStack.ps1` execute cette etape en phase 8. Le
parametre `-SkipDemoData` permet de la desactiver.

### Connexion Kibana

Ouvrir un tunnel :

```powershell
powershell -ExecutionPolicy Bypass -File `
  infra\k3s-vsphere\scripts\Open-Kibana.ps1
```

Conserver le terminal ouvert, puis utiliser :

```text
https://localhost:5601
```

Le certificat est auto-signe. Utiliser le compte `elastic` et recuperer son
mot de passe sans l'ecrire dans un fichier :

```powershell
$encoded = kubectl -n dockerelk get secret dockerelk-es-elastic-user `
  -o jsonpath='{.data.elastic}'
[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($encoded))
```

Lien direct :

```text
https://localhost:5601/app/dashboards#/view/dockerelk-infra-overview
```

### Visualisation attendue

Avec la periode `Last 24 hours`, le dashboard doit presenter :

1. un compteur d'evenements superieur ou egal au nombre injecte ;
2. une courbe CPU comprise entre `0` et `100 %`, avec des pointes critiques ;
3. trois barres de severite `info`, `warn` et `critical`.

Changer la periode temporelle ou filtrer sur `host.name`,
`event.severity` ou `service.name` doit recalculer les trois panneaux.

## Architecture

```text
Poste d'administration
  |-- Terraform
  |-- kubectl
  |-- OpenSSH
  |
  +--> vCenter / cluster ESXi
         |-- k3s-server-1  <IP_CONTROL_PLANE>
         |-- k3s-agent-1   <IP_WORKER_1>
         +-- k3s-agent-2   <IP_WORKER_2>

K3s
  |-- API Kubernetes TCP/6443
  |-- containerd
  +-- Argo CD namespace argocd
```

## Configuration anonymisee

Les valeurs ci-dessous illustrent la structure utilisee. Elles ne correspondent
pas aux identifiants, secrets ou adresses de l'environnement reel.

```hcl
vsphere_user         = "svc-terraform@vsphere.example"
vsphere_server       = "vcenter.example.internal"
allow_unverified_ssl = true # laboratoire uniquement

datacenter    = "LAB-DC"
cluster       = "LAB-CLUSTER"
datastore     = "LAB-DATASTORE"
network       = "LAB-PORTGROUP"
template_name = "Templates/ubuntu-2204-cloudinit-template"
vm_folder     = "LAB-K8S"

domain       = "example.internal"
ipv4_gateway = "192.0.2.1"
dns_servers  = ["192.0.2.53"]

nodes = {
  k3s-server-1 = {
    role         = "server"
    ipv4_address = "192.0.2.10"
    ipv4_netmask = 24
    num_cpus     = 2
    memory_mb    = 4096
    disk_size_gb = 30
  }
  k3s-agent-1 = {
    role         = "agent"
    ipv4_address = "192.0.2.11"
    ipv4_netmask = 24
    num_cpus     = 2
    memory_mb    = 4096
    disk_size_gb = 30
  }
  k3s-agent-2 = {
    role         = "agent"
    ipv4_address = "192.0.2.12"
    ipv4_netmask = 24
    num_cpus     = 2
    memory_mb    = 4096
    disk_size_gb = 30
  }
}
```

Les valeurs suivantes ne doivent jamais etre commitees :

- mot de passe vCenter ;
- jeton K3s ;
- cle privee SSH ;
- state et plans Terraform ;
- kubeconfig ;
- mot de passe administrateur initial Argo CD.

## Prerequis valides

- template `ubuntu-2204-cloudinit-template` deploye dans vCenter ;
- Ubuntu 22.04, `cloud-init` et `open-vm-tools` operationnels ;
- Terraform `1.15.6` ;
- provider `vmware/vsphere` `2.16.1` ;
- `kubectl` `1.36.0` ;
- OpenSSH disponible sur le poste d'administration ;
- trois IP statiques libres ;
- vCenter joignable sur TCP/443 ;
- sortie HTTPS autorisee depuis les VMs ;
- cle SSH dediee disponible au format OpenSSH.

La version de plateforme choisie est K3s `v1.36.1+k3s1`. Argo CD a ete
installe en version `v3.4.4`. Les versions sont epinglees pour rendre le
deploiement reproductible.

## Preparation du template

Pendant l'import OVF :

| Propriete | Valeur attendue |
| --- | --- |
| Instance ID | Valeur temporaire et non sensible |
| Hostname | Nom temporaire |
| Seed URL | Vide |
| Public key | Cle de test uniquement |
| Encoded user-data | Vide |

Avant conversion en template :

```bash
cloud-init status --wait
systemctl status open-vm-tools
sudo cloud-init clean --logs --machine-id
sudo shutdown -h now
```

Supprimer ensuite des proprietes vApp tout mot de passe, ancienne cle SSH ou
valeur propre a l'instance. Le template ne doit contenir aucun secret.

## Procedure executee

### 1. Preparation locale

1. Verification des outils Terraform, kubectl et SSH.
2. Verification de la connectivite HTTPS vers vCenter.
3. Verification que les trois adresses IP ne repondaient ni au ping ni dans
   la table ARP locale.
4. Generation initiale d'une cle SSH de deploiement.
5. Generation cryptographique d'un jeton K3s.
6. Creation de `terraform.tfvars` et `credentials.auto.tfvars`, ignores par Git.

### 2. Validation Terraform

```powershell
terraform fmt -recursive
terraform init -input=false
terraform validate
terraform plan -input=false -out=k3s.tfplan
terraform show k3s.tfplan
```

Plan valide :

```text
Plan: 3 to add, 0 to change, 0 to destroy.
```

Les objets vSphere resolus avant application etaient le datacenter, le cluster,
le datastore, le port group, le template et le resource pool attendus.

### 3. Application

```powershell
terraform apply -input=false -auto-approve k3s.tfplan
```

Resultat :

```text
Apply complete! Resources: 3 added, 0 changed, 0 destroyed.
```

Les trois VMs ont ete clonees en parallele, personnalisees avec leurs IP
statiques et demarrees.

### 4. Validation cloud-init et K3s

Pour chaque VM :

```bash
cloud-init status --wait
hostname -f
systemctl is-active k3s
systemctl is-active k3s-agent
```

Pour le cluster :

```powershell
.\infra\k3s-vsphere\scripts\Get-Kubeconfig.ps1 `
  -ServerIp <IP_CONTROL_PLANE>

.\infra\k3s-vsphere\scripts\Test-Cluster.ps1 `
  -Kubeconfig .\infra\k3s-vsphere\kubeconfig `
  -ExpectedNodes 3
```

Etat attendu :

```text
k3s-server-1   Ready   control-plane
k3s-agent-1    Ready
k3s-agent-2    Ready
```

### 5. Installation Argo CD

Le manifeste officiel epingle a `v3.4.4` a ete applique en mode server-side :

```bash
kubectl create namespace argocd
kubectl apply --server-side --force-conflicts \
  -n argocd \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/v3.4.4/manifests/install.yaml

kubectl wait -n argocd \
  --for=condition=Available \
  --timeout=600s \
  deployment/argocd-server
```

Le projet GitOps a ensuite ete cree :

```powershell
kubectl apply -f infra/k3s-vsphere/argocd/dockerelk-project.yaml
```

L'application ELK d'exemple n'a volontairement pas ete appliquee.

### 6. Rotation de la cle SSH

La paire definitive fournie au format PuTTY/OpenSSH a ete traitee ainsi :

1. conversion de la cle privee PuTTY en OpenSSH par l'operateur ;
2. derivation de la cle publique depuis la cle privee ;
3. comparaison des empreintes publique et privee ;
4. copie locale de la cle privee avec ACL restreintes ;
5. ajout idempotent de la nouvelle cle sur chaque VM ;
6. validation de la connexion sur les trois VMs ;
7. retrait de l'ancienne cle ED25519 ;
8. confirmation que la nouvelle cle est acceptee et l'ancienne refusee.

Une seule empreinte RSA attendue reste dans `authorized_keys` sur chaque VM.

## Incidents et corrections

### Terraform absent du PATH

**Symptome :**

```text
terraform n'est pas reconnu
```

**Cause :** `terraform.exe` etait installe dans le profil utilisateur sans etre
present dans `PATH`.

**Correction :** appel par chemin absolu. Recommandation : ajouter son dossier
au `PATH` utilisateur.

### Arguments Terraform mal interpretes

**Symptome :**

```text
Error: Too many command line arguments
```

**Cause :** interpretation PowerShell de la liste d'arguments.

**Correction :** transmettre chaque argument explicitement :

```powershell
& terraform.exe 'plan' '-input=false' '-out=k3s.tfplan'
```

### Lecteur CD-ROM requis

**Symptome :**

```text
this virtual machine requires a client CDROM device to deliver vApp properties
```

**Cause :** le template OVF utilise le transport vApp ISO.

**Correction Terraform :**

```hcl
cdrom {
  client_device = true
}
```

### CRD Argo CD trop volumineuse

**Symptome :**

```text
metadata.annotations: Too long: may not be more than 262144 bytes
```

**Cause :** l'apply client-side stockait une annotation trop volumineuse pour
une CRD Argo CD.

**Correction :**

```bash
kubectl apply --server-side --force-conflicts ...
```

Le script `argocd/install.sh` contient maintenant ce comportement.

### Kubeconfig non trouve

**Symptome :** `kubectl` tentait de joindre `http://localhost:8080`.

**Cause :** la variable `KUBECONFIG` etait construite depuis un repertoire
courant different de la racine du depot.

**Correction :**

```powershell
$env:KUBECONFIG="<CHEMIN_ABSOLU>\infra\k3s-vsphere\kubeconfig"
kubectl get nodes
```

### Proprietes vApp heritees sensibles

**Symptome :** le controle de derive Terraform a revele des proprietes vApp
heritees du template, dont un ancien mot de passe et une ancienne cle publique.

**Impact :** risque de duplication d'identifiants dans chaque clone et presence
de donnees sensibles dans le state ou les sorties de plan.

**Mesures prises :**

- verification que `PasswordAuthentication` et
  `KbdInteractiveAuthentication` valent `no` ;
- verification que le mot de passe du compte Ubuntu est verrouille ;
- rotation des cles SSH ;
- ajout de `ignore_changes = [vapp]` pour eviter une suppression implicite ;
- documentation de l'assainissement obligatoire du template source.

**Action restante :** nettoyer les proprietes vApp du template dans vCenter,
puis evaluer le retrait de `ignore_changes` apres validation d'un clone neuf.

### Rotation SSH : formats et fins de ligne

**Problemes rencontres :**

- cle publique initiale au format RFC4716/SSH2 ;
- cle privee PuTTY `.ppk` a convertir en OpenSSH ;
- PuTTYgen difficile a piloter avec un chemin contenant des espaces ;
- retrait textuel initial inefficace a cause du commentaire et des fins de ligne.

**Correction :**

- derivation de la cle publique avec `ssh-keygen -y` ;
- comparaison des empreintes SHA-256 ;
- test de la nouvelle cle avant retrait de l'ancienne ;
- retrait cible de l'ancienne ligne ED25519 ;
- validation positive et negative sur chaque VM.

## Etat final attendu

### Terraform

```text
3 VMs suivies dans le state
0 ressource non geree parmi les VMs du cluster
terraform validate: Success
```

Un `terraform plan` final doit afficher :

```text
No changes. Your infrastructure matches the configuration.
```

Ce dernier controle doit etre execute apres toute modification manuelle du
template ou des VMs.

### Kubernetes

```powershell
kubectl get nodes -o wide
kubectl get pods -A
```

Attendus :

- trois noeuds `Ready` ;
- control-plane sur `k3s-server-1` ;
- services K3s actifs ;
- pods systeme K3s en etat `Running` ou `Completed`.

### Argo CD

```powershell
kubectl get pods -n argocd
kubectl get appproject -n argocd dockerelk-v2
```

Attendus :

- sept composants Argo CD `Running` et `Ready` ;
- projet `dockerelk-v2` present ;
- aucune application ELK active tant que les manifests de production ne sont
  pas valides.

## Acces operateur

Control-plane :

```powershell
ssh -i "$HOME\.ssh\<CLE_PRIVEE>" ubuntu@<IP_CONTROL_PLANE>
```

Administration Kubernetes :

```powershell
$env:KUBECONFIG="<CHEMIN_ABSOLU>\infra\k3s-vsphere\kubeconfig"
kubectl get nodes -o wide
kubectl get pods -A
```

Acces temporaire a Argo CD :

```powershell
kubectl port-forward -n argocd service/argocd-server 8080:443
```

Puis ouvrir `https://localhost:8080`. Le compte initial est `admin`. Le mot de
passe initial doit etre lu depuis le secret Kubernetes, change immediatement,
puis le secret initial doit etre supprime.

## Securite et exploitation

- ne jamais commiter `*.tfvars`, `*.tfstate*`, `*.tfplan`, `kubeconfig` ou une
  cle privee ;
- chiffrer et externaliser le state Terraform avant un usage en equipe ;
- remplacer `allow_unverified_ssl = true` apres deploiement d'un certificat
  vCenter de confiance ;
- sauvegarder le datastore K3s avant une evolution majeure ;
- lire les notes de version avant toute mise a jour K3s ou Argo CD ;
- maintenir un acces console vCenter pendant une rotation SSH ;
- ne pas utiliser le mot de passe initial Argo CD comme secret permanent ;
- ne pas deployer Elasticsearch sans StorageClass, snapshots et strategie de
  restauration valides.

## Rollback et destruction

Une destruction supprime les VMs et leurs donnees locales :

```powershell
terraform plan -destroy -out destroy.tfplan
terraform show destroy.tfplan
terraform apply destroy.tfplan
```

Avant application :

- sauvegarder les donnees persistantes ;
- exporter les manifests et secrets necessaires ;
- confirmer que le plan ne cible que les trois VMs attendues ;
- conserver le template Ubuntu ;
- obtenir une validation humaine explicite.

La destruction Terraform n'est pas une strategie de restauration des donnees.

## Fichiers associes

```text
infra/k3s-vsphere/
  README.md
  terraform/
    main.tf
    variables.tf
    outputs.tf
    cloud-init/
  scripts/
    Get-Kubeconfig.ps1
    Test-Cluster.ps1
  argocd/
    install.sh
    dockerelk-project.yaml
tests/
  Test-K3sVsphereModule.ps1
```
