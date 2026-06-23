# Merge log - Techapple78/DockerELK

## Contexte

Objectif : auditer, corriger et valider la stack Docker ELK avant merge vers `Techapple78/DockerELK`.

Branche locale : `main`

Date de validation : 2026-06-23

## Problemes rencontres et corrections

### Docker Compose

- `docker-compose.yml` utilisait l'attribut obsolete `version`.
  - Impact : avertissement systematique avec Docker Compose v5.
  - Correction : suppression de `version`.

- Les services etaient nommes `Elastic`, `Logstash`, `Kibana`, alors que les configs utilisaient `elasticsearch`.
  - Impact : resolution DNS Docker incoherente entre services.
  - Correction : renommage Compose en `elasticsearch`, `logstash`, `kibana`.

- `links` etait encore utilise pour Kibana.
  - Impact : configuration hereditee inutile avec un reseau Compose.
  - Correction : suppression de `links`.

- Elasticsearch montait `Elastic/config/jvm.options` et `Elastic/config/log4j2.properties`, absents du repo.
  - Impact : risque de bind mounts invalides et demarrage fragile.
  - Correction : suppression de ces mounts, conservation des defaults fournis par le paquet.

### Elasticsearch

- La config Elasticsearch etait montee vers `/usr/share/elasticsearch/config/elasticsearch.yml`, mais le paquet Debian lit `/etc/elasticsearch/elasticsearch.yml`.
  - Impact : Elasticsearch ignorait `network.host: 0.0.0.0` et se bindait sur `127.0.0.1` dans le conteneur.
  - Correction : mount Compose et `COPY` Dockerfile deplaces vers `/etc/elasticsearch`.

- Apres remplacement de la config paquet, `path.data` et `path.logs` n'etaient plus explicites.
  - Impact : crash runtime avec `Unable to access 'path.logs' (/usr/share/elasticsearch/logs)`.
  - Correction : ajout de `path.data: /usr/share/elasticsearch/data` et `path.logs: /var/log/elasticsearch`.

- Le playbook utilisait une commande shell avec pipe pour ajouter le depot Elastic.
  - Impact : fragile et moins idempotent.
  - Correction : remplacement par le module Ansible `apt_repository`.

### Logstash

- La sortie Elasticsearch pointait vers `localhost:9200`.
  - Impact : dans le conteneur Logstash, `localhost` ne pointe pas vers Elasticsearch.
  - Correction : sortie vers `elasticsearch:9200`.

- Deux inputs utilisaient le meme port `5044` (`tcp` et `beats`).
  - Impact : erreur runtime `Address already in use`, redemarrage du plugin input.
  - Correction : suppression de l'input `beats` en doublon, conservation de l'input `tcp`.

- Le playbook utilisait l'ancien depot `https://packages.elastic.co/logstash/6.3/debian`.
  - Impact : echec Ansible `apt cache update failed`.
  - Correction : depot remplace par `https://artifacts.elastic.co/packages/6.x/apt`.

- Le Dockerfile utilisait `PATH /opt/logstash/bin`.
  - Impact : `docker run dockerelk_logstash --version` echouait avec `runuser: failed to execute logstash`.
  - Correction : `PATH` mis a jour vers `/usr/share/logstash/bin`.

- Le `CMD` Logstash utilisait l'ancien format `logstash agent -f /etc/logstash/conf.d/`.
  - Impact : incoherent avec Logstash 6.x et la config montee dans `/usr/share/logstash/config`.
  - Correction : `CMD ["logstash", "--path.settings", "/usr/share/logstash/config"]`.

- Le fichier etait nomme `Logstash/dockerfile`.
  - Impact : ambiguite sur plateformes sensibles a la casse.
  - Correction : renommage filesystem en `Logstash/Dockerfile`.

### Kibana

- Le playbook Kibana ajoutait le depot avec une commande pipe non shell (`command: echo ... | tee ...`).
  - Impact : le depot n'etait pas ajoute correctement ; build KO avec `No package matching 'kibana' is available`.
  - Correction : remplacement par `apt_repository` avec `https://artifacts.elastic.co/packages/6.x/apt`.

- Le playbook ciblait `/opt/kibana`, ancien layout.
  - Impact : build KO avec `file (/opt/kibana) is absent`.
  - Correction : chemin remplace par `/usr/share/kibana`.

- Le playbook essayait de modifier `/usr/share/kibana/config/kibana.yml`, absent au build.
  - Impact : build KO avec `Path /usr/share/kibana/config/kibana.yml does not exist`.
  - Correction : suppression de cette modification build-time ; la config runtime vient de `Kibana/config/kibana.yml` via Compose.

- Le Dockerfile utilisait `PATH /opt/kibana/bin`.
  - Impact : chemin binaire obsolete pour le paquet installe.
  - Correction : `PATH` mis a jour vers `/usr/share/kibana/bin`.

### Entrypoints

- Les trois scripts utilisaient `#!/bin/sh` avec `${1:0:1}`.
  - Impact : syntaxe non POSIX, susceptible de casser sous `dash` avec `Bad substitution`.
  - Correction : remplacement par `case "$1" in -*) ...`.

- Les entrypoints Logstash et Kibana etaient des copies de celui d'Elasticsearch.
  - Impact : injection de la commande `elasticsearch` pour des options CLI, commentaires et utilisateurs incorrects.
  - Correction : entrypoint propre par service :
    - Elasticsearch : commande `elasticsearch`, utilisateur `elasticsearch`.
    - Logstash : commande `logstash`, utilisateur `logstash`.
    - Kibana : commande `kibana`, utilisateur `kibana`.

### Documentation

- `README.md` contenait du texte avec encodage casse (`BasÃ©`, etc.).
  - Impact : documentation difficile a lire.
  - Correction : README reecrit en ASCII avec commandes Docker Compose modernes et tests de validation.

## Problemes d'environnement rencontres

- `ansible-playbook.exe` installe via `pip --user` n'etait pas dans le `PATH`.
- Appel direct via `C:\Users\AntaresXI\AppData\Roaming\Python\Python310\Scripts\ansible-playbook.exe` KO :
  - `AttributeError: module 'os' has no attribute 'get_blocking'`.
- WSL etait disponible mais sans distribution installee.
- Les `syntax-check` Ansible ont donc ete executes via Docker, dans l'image construite.
- Premier build Docker KO car Docker Desktop/daemon Linux n'etait pas disponible ; apres relance, le daemon etait disponible.

## Validations realisees

Commandes de validation :

```console
docker compose config
docker compose build elasticsearch
docker compose build logstash
docker compose build kibana
docker compose build
docker compose up -d --build --force-recreate
```

Tests entrypoints :

```console
docker run --rm dockerelk_elastic --version
docker run --rm dockerelk_logstash --version
docker run --rm dockerelk_kibana --version
```

Tests HTTP :

- `http://localhost:9200` : OK, Elasticsearch `6.8.23`.
- `http://localhost:5601` : OK, statut `200`.

Test ingestion Logstash :

- Envoi d'une ligne nginx vers TCP `5044`.
- Index cree : `logstash-local-dev-2026.06.23`.
- Verification `_count` : `1`.

Etat final observe :

- `elasticsearch` : Up
- `logstash` : Up
- `kibana` : Up

## Dette restante

- Base `ubuntu:16.04` toujours EOL.
- Elastic Stack resolue en `6.8.23`, version elle aussi EOL.
- Une migration de securite vers une version moderne doit etre traitee dans un lot dedie.
- Le dossier `.data/` est un artefact runtime local cree par Elasticsearch pendant les tests et ne doit pas etre commite.

## Proposition de message de merge/commit

```text
fix: restore Docker ELK build and runtime integration

- align Compose service names and remove obsolete links/version
- fix Elasticsearch config path, data/log paths, and missing mounts
- update Elastic apt repositories through Ansible apt_repository
- fix Kibana and Logstash package layouts for Elastic 6.x
- replace copied entrypoints with service-specific POSIX scripts
- fix Logstash output host and duplicate 5044 input
- refresh README and document validation commands
```
