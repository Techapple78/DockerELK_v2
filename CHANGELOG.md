# Changelog

Toutes les modifications notables de ce projet sont documentees dans ce fichier.

Le format suit l'esprit de [Keep a Changelog](https://keepachangelog.com/) et les commits suivent Conventional Commits lorsque possible.

## [v2.0.0-migration] - 2026-06-23

### Added

- Ajout du rapport de migration v1 vers v2 :
  - `docs/migrations/2026-06-23_v1-to-v2_data-migration-report.md`
  - strategie Git complete;
  - arborescence cible;
  - sequence de commits Conventional Commits;
  - scripts migration et rollback attendus;
  - strategie de test;
  - checklists migration, rollback et release;
  - risques principaux et mitigations.
- Ajout des topologies Docker Compose de validation parallele :
  - `docker-compose.staging.yml`
  - `docker-compose.logstash-scale.yml`
  - `docker-compose.elasticsearch-cluster.yml`
  - `docker-compose.kibana-scale.yml`
- Ajout d'une configuration Elasticsearch cluster 3 noeuds :
  - `Elastic/config/elasticsearch-cluster.yml`
- Ajout de scripts PowerShell de validation :
  - `tests/Smoke-Test.ps1`
  - `tests/Send-TestEvent.ps1`
  - `tests/Verify-Ingestion.ps1`
- Ajout de `.gitattributes` pour stabiliser les fins de ligne, notamment les entrypoints shell.
- Ajout des repertoires de donnees de test `.data-*` dans `.gitignore`.
- Ajout d'une documentation README pour :
  - les tests de scalabilite horizontale;
  - les ports par topologie;
  - les commandes smoke test;
  - les tests d'ingestion;
  - le deploiement controle sur la stack principale.

### Changed

- Renommage cible du projet documente vers `DockerELK_v2`.
- Normalisation des entrypoints shell Docker pour eviter les problemes d'execution lies aux fins de ligne Windows.
- Clarification de l'approche de validation :
  - staging parallele avant production;
  - test Logstash horizontal;
  - test Elasticsearch 3 noeuds;
  - test Kibana horizontal;
  - validation finale sur la stack principale.
- Publication de la branche de migration vers le depot `Techapple78/DockerELK_v2` :
  - branche `migration/v1-to-v2-data-refactor`;
  - commit `2ff68f9 feat(scalability): add DockerELK v2 migration and scale validation`.

### Fixed

- Correction de la connectivite interne Docker autour du hostname Elasticsearch.
- Correction des risques d'echec des entrypoints shell lies a des substitutions incompatibles avec `/bin/sh`.
- Correction de l'execution des scripts de test PowerShell :
  - interpolation d'URL;
  - generation de timestamp stable;
  - verification d'ingestion sur les index `logstash-local-dev-*`.
- Resolution d'un blocage de cluster Elasticsearch de test cause par les watermarks disque Docker Desktop, avec un reglage limite au laboratoire de scalabilite.

### Security

- Audit et documentation du risque lie a Ubuntu 16.04 et Elastic Stack 6.x, versions anciennes et a migrer avant un usage production durable.
- Documentation d'une strategie de rollback obligatoire avant release `v2.0.0`.
- Conservation de la stack principale allumee pendant la destruction des stacks de test.

### Validation

- Validation Docker Compose :
  - `docker compose -f docker-compose.yml config`
  - `docker compose -f docker-compose.staging.yml config`
  - `docker compose -f docker-compose.logstash-scale.yml config`
  - `docker compose -f docker-compose.elasticsearch-cluster.yml config`
  - `docker compose -f docker-compose.kibana-scale.yml config`
- Validation staging parallele :
  - Elasticsearch OK;
  - Kibana OK;
  - Logstash TCP OK;
  - ingestion OK.
- Validation Logstash horizontal :
  - deux instances Logstash testees;
  - ingestion OK depuis les deux ports.
- Validation Elasticsearch cluster :
  - cluster 3 noeuds OK;
  - etat `green` apres stabilisation;
  - ingestion OK;
  - test de perte d'un noeud avec maintien de l'ingestion.
- Validation Kibana horizontal :
  - deux instances Kibana OK;
  - ingestion Logstash -> Elasticsearch OK.
- Validation production :
  - Elasticsearch `http://localhost:9200` OK;
  - Kibana `http://localhost:5601` OK;
  - Logstash `localhost:5044` OK;
  - ingestion finale OK.

### Operations

- Destruction des stacks de test apres audit :
  - `docker-compose.staging.yml`
  - `docker-compose.logstash-scale.yml`
  - `docker-compose.elasticsearch-cluster.yml`
  - `docker-compose.kibana-scale.yml`
- Conservation de la stack principale `docker-compose.yml` allumee.
- Les volumes/dossiers `.data-*` de test n'ont pas ete supprimes par mesure de prudence.

### Known Issues

- Le projet utilise encore Ubuntu 16.04 et Elastic Stack 6.x.
- La migration vers une version Elastic recente doit etre traitee comme un chantier dedie, avec tests de compatibilite, migration d'index et validation Kibana.
- Le reglage `cluster.routing.allocation.disk.threshold_enabled: false` est reserve au laboratoire Docker Desktop et ne doit pas etre repris tel quel en production.

