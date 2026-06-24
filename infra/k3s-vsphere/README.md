# K3s sur vSphere

Ce module provisionne un cluster K3s de laboratoire sur vCenter :

- `k3s-server-1` : control-plane ;
- `k3s-agent-1` : worker ;
- `k3s-agent-2` : worker.

Terraform clone trois VMs Ubuntu 22.04, vSphere applique le reseau statique,
cloud-init installe K3s, puis Argo CD peut etre initialise sur le cluster.

Le module ne deploie pas encore ELK. Le manifeste Argo CD d'application reste
un exemple tant que la revision Git contenant les manifests Kubernetes n'est
pas publiee.

## Prerequis

- vCenter et un cluster ESXi joignables depuis le poste Terraform ;
- Terraform 1.6 ou plus recent ;
- `kubectl`, `ssh` et PowerShell 7 sur le poste d'administration ;
- droits vCenter pour lire l'inventaire, cloner, configurer et supprimer les VMs ;
- trois adresses IP disponibles, une passerelle et un ou plusieurs serveurs DNS ;
- resolution DNS directe et inverse recommandee pour les trois noms ;
- sortie HTTPS des VMs vers `get.k3s.io`, GitHub et les registries de conteneurs ;
- ports internes autorises : TCP `6443`, `10250`, `2379-2380` et UDP `8472` ;
- stockage distant securise pour le state Terraform en environnement partage.

## Template Ubuntu

Importer l'image cloud officielle Ubuntu 22.04 dans vCenter, puis preparer un
template nomme `ubuntu-2204-cloudinit-template`.

Pendant l'etape **Personnaliser un modele** du deploiement OVF, utiliser :

| Champ OVF | Valeur |
| --- | --- |
| Unique Instance ID | `ubuntu-2204-template` |
| Hostname | `ubuntu-template` |
| URL to seed instance data | Laisser vide |
| SSH public keys | Cle publique SSH de l'administrateur, recommandee pour le test initial |
| Encoded user-data | Laisser vide |

Ne pas saisir a cette etape les adresses IP, le jeton K3s ou le user-data
definitif. Ces valeurs seront injectees par Terraform lors du clonage.

Le template doit contenir :

- `cloud-init` actif ;
- `open-vm-tools` actif ;
- une carte reseau compatible avec la personnalisation vSphere ;
- aucun identifiant machine ou cle SSH propre a une ancienne VM ;
- un disque dont la taille ne depasse pas celle demandee dans `nodes`.

Apres le deploiement de l'OVA :

1. Demarrer la VM une premiere fois.
2. Se connecter avec la cle SSH fournie pendant le deploiement.
3. Verifier cloud-init et VMware Tools :

```bash
cloud-init status --wait
systemctl status open-vm-tools
```

4. Nettoyer les donnees propres a cette instance, puis l'arreter :

```bash
sudo cloud-init clean --logs --machine-id
sudo shutdown -h now
```

5. Dans les proprietes vApp de la VM, supprimer tout mot de passe, ancienne cle
   SSH et valeur propre a l'instance. Ne conserver aucun secret dans le
   template.
6. Dans vCenter, convertir la VM en template.
7. Nommer le template `ubuntu-2204-cloudinit-template`.

Tester ensuite le template avec un clone manuel avant le premier
`terraform apply`. Verifier notamment que la datasource VMware traite bien le
`guestinfo.userdata` injecte par Terraform, que l'authentification SSH par mot
de passe est desactivee et que seuls les acces par cle attendus fonctionnent.

## Configuration

Depuis `infra/k3s-vsphere/terraform` :

```powershell
Copy-Item terraform.tfvars.example terraform.tfvars
```

Renseigner les objets vCenter, les IP statiques, la cle SSH et les secrets.
Generer le jeton K3s avec :

```powershell
openssl rand -hex 32
```

`terraform.tfvars`, le state et le kubeconfig sont ignores par Git. Le state
contient toutefois le jeton K3s et doit etre chiffre et controle par ACL.

La version K3s doit etre choisie explicitement apres lecture des notes de
version, puis remplacer `vX.Y.Z+k3sN` dans `terraform.tfvars`. Ne pas utiliser
un canal flottant pour une plateforme reproductible.

## Validation Terraform

```powershell
Set-Location infra/k3s-vsphere/terraform
terraform fmt -recursive -check
terraform init
terraform validate
terraform plan -out k3s.tfplan
terraform show k3s.tfplan
```

Verifier avant application :

- les trois noms et adresses IP ;
- le template, le datastore, le port group et le dossier ;
- l'absence de suppression ou remplacement inattendu ;
- `allow_unverified_ssl = false` hors laboratoire.

## Deploiement

```powershell
terraform apply k3s.tfplan
terraform output node_ips
```

Suivre cloud-init sur une VM en cas de besoin :

```bash
sudo cloud-init status --wait
sudo journalctl -u k3s -u k3s-agent --no-pager
```

Recuperer puis tester le kubeconfig :

```powershell
Set-Location ..
.\scripts\Get-Kubeconfig.ps1 -ServerIp 192.0.2.10
.\scripts\Test-Cluster.ps1 -Kubeconfig .\kubeconfig -ExpectedNodes 3
```

## Argo CD

Choisir une version publiee et lire ses notes de version, puis depuis une
machine disposant de Bash et du kubeconfig :

```bash
export KUBECONFIG=./kubeconfig
./argocd/install.sh v3.4.4
kubectl apply -f argocd/dockerelk-project.yaml
```

Le script utilise le mode server-side apply, requis pour eviter la limite de
taille des annotations client-side sur les CRD Argo CD.

## Deploiement Elastic Stack

Le profil K3s de laboratoire utilise :

- ECK `3.4.0` ;
- Elasticsearch, Logstash et Kibana `9.4.2` ;
- un noeud Elasticsearch avec PVC local `15 Gi` ;
- Kibana sur le NodePort `30601` ;
- Logstash TCP JSON sur le NodePort `30514`.

Deployer et tester toute la chaine :

```powershell
.\scripts\Deploy-ElasticStack.ps1 -Kubeconfig ..\kubeconfig
```

Cette commande ajoute aussi `240` evenements de demonstration et cree le
dashboard Kibana `DockerELK Infrastructure Overview`. Utiliser
`-SkipDemoData` pour ne pas alimenter la demonstration.

Rejouer uniquement le test d'integration :

```powershell
.\scripts\Test-ElasticStack.ps1 -Kubeconfig ..\kubeconfig
```

Recreer uniquement les donnees et le dashboard :

```powershell
.\scripts\Seed-ElasticDemo.ps1 -Kubeconfig ..\kubeconfig
```

Kibana :

```text
https://<IP_D_UN_NOEUD>:30601
```

Acces recommande par tunnel local :

```powershell
.\scripts\Open-Kibana.ps1 -Kubeconfig ..\kubeconfig
```

Puis ouvrir :

```text
https://localhost:5601/app/dashboards#/view/dockerelk-infra-overview
```

Le navigateur signale le certificat auto-signe. Le compte est `elastic` et le
mot de passe est lu depuis `dockerelk-es-elastic-user`.

Le dashboard affiche sur les dernieres 24 heures :

- le nombre total d'evenements infrastructure ;
- la moyenne CPU par tranche de 30 minutes ;
- la repartition `info`, `warn` et `critical`.

Les evenements couvrent six hotes et services fictifs avec des mesures CPU,
memoire, disque et temps de reponse.

Recuperer le mot de passe `elastic` sans l'ecrire dans le depot :

```powershell
$encoded = kubectl -n dockerelk get secret dockerelk-es-elastic-user `
  -o jsonpath='{.data.elastic}'
[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($encoded))
```

Apres publication des manifests sur la branche distante, transferer la gestion
a Argo CD :

```powershell
.\scripts\Register-ElasticGitOps.ps1
```

Le script refuse l'enregistrement si l'overlay n'est pas joignable dans Git.
Ce profil mono-noeud avec stockage `local-path` est un laboratoire persistant,
pas une architecture Elasticsearch hautement disponible.

## Destruction

Sauvegarder les donnees persistantes avant toute destruction. Afficher le plan,
puis demander une validation humaine :

```powershell
Set-Location terraform
terraform plan -destroy -out destroy.tfplan
terraform show destroy.tfplan
terraform apply destroy.tfplan
```

La suppression des VMs ne constitue pas une procedure de sauvegarde ou de
rollback des donnees Elasticsearch.
