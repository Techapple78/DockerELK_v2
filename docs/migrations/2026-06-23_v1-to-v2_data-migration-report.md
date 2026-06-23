# Rapport de migration - v1 vers v2

## Metadonnees

| Champ | Valeur |
| --- | --- |
| Projet | `DockerELK_v2` |
| Depot source | `Techapple78/DockerELK` |
| Version source | `v1.x.x` |
| Version cible | `v2.0.0` |
| Branche Git | `migration/v1-to-v2-data-refactor` |
| Pull Request | `[MIGRATION] v1 -> v2 - refactor + data migration` |
| Date du rapport | `2026-06-23` |
| Responsable technique | A renseigner |
| Validateur metier / delivery | A renseigner |
| Environnement cible | `dev -> staging -> production` |
| Statut | `draft` |

## 1. Synthese executive

La version `v1` de DockerELK a deja ete modifiee et doit etre refondue vers une version `v2` nommee `DockerELK_v2`. La migration doit couvrir la structure du depot, la configuration de la stack, les donnees persistantes Elasticsearch, la documentation d'exploitation, les tests et le rollback.

Le tag `v2.0.0` est justifie si la migration introduit une rupture de compatibilite avec `v1`, par exemple un changement de noms de services, de volumes, de ports exposes, de modeles d'index Elasticsearch, de dashboards Kibana, de pipeline Logstash ou de procedure de deploiement.

## 2. Objectifs

1. Tracer toute la migration dans Git.
2. Isoler le travail sur une branche dediee.
3. Documenter la strategie de migration et de rollback.
4. Preparer les scripts de migration et de retour arriere.
5. Valider la migration par tests unitaires, integration, smoke tests et dry-run.
6. Mettre a jour le changelog et la documentation.
7. Publier une release taguee `v2.0.0`.

## 3. Strategie Git complete

### Branche de migration

```bash
git checkout master
git pull origin master
git checkout -b migration/v1-to-v2-data-refactor
```

La branche `migration/v1-to-v2-data-refactor` concentre tout le travail de migration. Aucun changement direct ne doit etre pousse sur `master`.

### Convention de nommage

| Element | Nom |
| --- | --- |
| Branche | `migration/v1-to-v2-data-refactor` |
| Rapport | `docs/migrations/2026-06-23_v1-to-v2_data-migration-report.md` |
| Script migration | `migrations/20260623_001_v1_to_v2_schema_and_data.sql` |
| Script rollback | `migrations/rollback/20260623_001_v2_to_v1_rollback.sql` |
| Pull Request | `[MIGRATION] v1 -> v2 - refactor + data migration` |
| Tag release | `v2.0.0` |

### Regles de commit

- Commits atomiques et relisibles.
- Messages au format Conventional Commits.
- Un commit par intention technique.
- Les scripts de migration, rollback, tests et documentation doivent etre versionnes.
- Aucun tag `v2.0.0` avant validation complete et merge.

## 4. Arborescence cible du depot

```text
.
|-- CHANGELOG.md
|-- README.md
|-- docker-compose.yml
|-- docker-compose.staging.yml
|-- docker-compose.logstash-scale.yml
|-- docker-compose.elasticsearch-cluster.yml
|-- docker-compose.kibana-scale.yml
|-- docs/
|   |-- migrations/
|   |   `-- 2026-06-23_v1-to-v2_data-migration-report.md
|   `-- adr/
|       `-- 0001-v1-to-v2-architecture-decision.md
|-- migrations/
|   |-- 20260623_001_v1_to_v2_schema_and_data.sql
|   `-- rollback/
|       `-- 20260623_001_v2_to_v1_rollback.sql
|-- tests/
|   |-- Smoke-Test.ps1
|   |-- Send-TestEvent.ps1
|   |-- Verify-Ingestion.ps1
|   `-- migration/
|       |-- v1_to_v2_dry_run.test.ps1
|       `-- v1_to_v2_integrity.test.ps1
|-- Elastic/
|-- Logstash/
`-- Kibana/
```

## 5. Sequence de commits attendue

```bash
git commit -m "chore(project): rename project to DockerELK_v2"
git commit -m "refactor(v2): restructure DockerELK v1 deployment layout"
git commit -m "feat(migration): add v1 to v2 schema and data migration script"
git commit -m "feat(migration): add v2 to v1 rollback script"
git commit -m "test(migration): add v1 to v2 dry-run checks"
git commit -m "test(integration): validate DockerELK_v2 stack deployment"
git commit -m "docs(migration): add v1 to v2 migration report"
git commit -m "docs(runbook): document v2 deployment and rollback procedures"
git commit -m "docs(changelog): document v2.0.0 migration changes"
git commit -m "ci(migration): add migration validation workflow"
git commit -m "chore(release): prepare v2.0.0"
```

Ordre recommande :

1. Renommage et metadata projet.
2. Refactor de structure.
3. Migration.
4. Rollback.
5. Tests.
6. Documentation.
7. Changelog.
8. CI.
9. Release candidate.

## 6. Scripts de migration

### Script cible

```text
migrations/20260623_001_v1_to_v2_schema_and_data.sql
```

### Principes

- Le script doit etre idempotent lorsque possible.
- Les operations destructrices doivent etre evitees ou isolees derriere une sauvegarde.
- Les changements de schema doivent etre separes logiquement des transformations de donnees.
- Les controles avant/apres doivent etre inclus ou accompagnes de requetes de verification.
- Le script doit journaliser les etapes critiques si le moteur de donnees le permet.

### Squelette recommande

```sql
-- Migration: v1 -> v2
-- Projet: DockerELK_v2
-- Date: 2026-06-23

BEGIN;

-- 1. Pre-checks
-- Verifier l'existence des tables/index/collections source.

-- 2. Schema changes
-- Utiliser IF EXISTS / IF NOT EXISTS lorsque disponible.

-- 3. Data transformation
-- Preferer INSERT ... SELECT avec clauses anti-doublons.

-- 4. Integrity checks
-- Comparer les volumes et detecter les donnees orphelines.

COMMIT;
```

Pour Elasticsearch, l'equivalent peut etre porte par des appels API versionnes :

- creation de nouveaux index templates `v2`;
- reindexation depuis les index `v1`;
- verification `_count`;
- bascule d'alias;
- conservation temporaire des index `v1`.

## 7. Script de rollback

### Script cible

```text
migrations/rollback/20260623_001_v2_to_v1_rollback.sql
```

### Principes

- Le rollback doit documenter ce qui est reversible et ce qui ne l'est pas.
- Les donnees `v1` doivent etre conservees jusqu'a validation post-migration.
- Les alias ou pointeurs applicatifs doivent pouvoir revenir vers les index `v1`.
- Une restauration de backup doit rester le plan de secours si la transformation est destructive.

### Squelette recommande

```sql
-- Rollback: v2 -> v1
-- Projet: DockerELK_v2
-- Date: 2026-06-23

BEGIN;

-- 1. Stopper les ecritures applicatives.
-- 2. Retablir les structures v1 si necessaire.
-- 3. Rebasculer les pointeurs/alias vers v1.
-- 4. Verifier les volumes et controles d'integrite.

COMMIT;
```

## 8. Strategie de test

| Niveau | Objectif | Commande / preuve attendue |
| --- | --- | --- |
| Tests unitaires | Valider les fonctions de parsing, transformation et generation de config | Commande projet a definir |
| Tests migration dry-run | Executer la migration sur copie de donnees | `tests/migration/v1_to_v2_dry_run.test.ps1` |
| Tests integration | Verifier ES, Logstash, Kibana ensemble | `tests/Smoke-Test.ps1` |
| Tests ingestion | Envoyer un event et verifier l'indexation | `tests/Send-TestEvent.ps1` puis `tests/Verify-Ingestion.ps1` |
| Tests rollback | Revenir vers v1 sur environnement de test | Script rollback + controles d'integrite |
| Tests performance | Evaluer temps de migration et impact ressources | Rapport de dry-run |
| Tests securite | Verifier secrets, ports, surfaces exposees et versions | Audit manuel + scan si disponible |

### Ordre de validation

1. `docker compose config`
2. Build images.
3. Smoke test staging.
4. Dry-run migration sur donnees copiees.
5. Verification des volumes de donnees.
6. Test rollback sur staging.
7. Test de redeploiement complet.
8. Validation delivery.

## 9. Checklist pre-migration

- [ ] Branche `migration/v1-to-v2-data-refactor` creee depuis `master`.
- [ ] Perimetre de migration valide.
- [ ] Nom projet cible `DockerELK_v2` valide.
- [ ] Sauvegarde complete disponible.
- [ ] Procedure de restauration testee.
- [ ] Script migration relu par DevOps + backend + DBA.
- [ ] Script rollback relu par DevOps + backend + DBA.
- [ ] Dry-run execute sur staging.
- [ ] Tests unitaires executes.
- [ ] Tests integration executes.
- [ ] Tests ingestion executes.
- [ ] Tests rollback executes.
- [ ] Changelog mis a jour.
- [ ] Documentation mise a jour.
- [ ] Fenetre de maintenance validee si production.
- [ ] Critere de rollback partage avec delivery.

## 10. Checklist migration

- [ ] Geler ou limiter les ecritures applicatives.
- [ ] Confirmer la sauvegarde pre-migration.
- [ ] Relever l'etat initial : version, containers, index, volumes, counts.
- [ ] Deployer les artefacts `DockerELK_v2` en staging.
- [ ] Executer le script migration.
- [ ] Verifier les logs migration.
- [ ] Controler les donnees migrees.
- [ ] Executer les tests d'integration.
- [ ] Executer les tests d'ingestion.
- [ ] Valider Kibana et dashboards.
- [ ] Ouvrir la Pull Request.
- [ ] Obtenir les validations techniques et delivery.

## 11. Checklist rollback

- [ ] Declarer l'incident ou le critere de rollback.
- [ ] Stopper les ecritures `v2`.
- [ ] Sauvegarder l'etat d'echec pour analyse.
- [ ] Executer `migrations/rollback/20260623_001_v2_to_v1_rollback.sql` ou restaurer le backup.
- [ ] Rebasculer les alias, volumes ou endpoints vers `v1`.
- [ ] Redemarrer la stack `v1`.
- [ ] Verifier Elasticsearch, Logstash et Kibana.
- [ ] Executer les tests smoke.
- [ ] Controler les donnees critiques.
- [ ] Documenter la cause et les actions correctives.
- [ ] Bloquer la release `v2.0.0` tant que le correctif n'est pas valide.

## 12. Procedure de release `v2.0.0`

### Preparation

```bash
git checkout migration/v1-to-v2-data-refactor
git status
git log --oneline --decorate -n 20
```

### Pull Request

Titre :

```text
[MIGRATION] v1 -> v2 - refactor + data migration
```

Contenu minimum :

- contexte et objectifs;
- liste des commits;
- risques;
- resultats des tests;
- procedure de migration;
- procedure de rollback;
- decision sur le caractere breaking change.

### Merge

```bash
git checkout master
git pull origin master
git merge --no-ff migration/v1-to-v2-data-refactor
```

Ou merge via Pull Request GitHub apres validations.

### Tag

```bash
git tag -a v2.0.0 -m "Release v2.0.0 - v1 to v2 refactor and data migration"
git push origin v2.0.0
```

### Publication

- Publier les release notes.
- Joindre le rapport de migration.
- Lier le changelog.
- Archiver les resultats de tests.
- Conserver les backups selon la politique de retention.

## 13. Changelog attendu

Creer ou mettre a jour `CHANGELOG.md` :

```markdown
# Changelog

## [v2.0.0] - 2026-06-23

### Breaking Changes
- Renommage projet vers DockerELK_v2.
- Migration v1 vers v2 avec adaptation du modele de donnees.

### Added
- Scripts de migration et rollback.
- Rapport de migration.
- Tests de validation migration.

### Changed
- Structure de deploiement et documentation d'exploitation.

### Security
- Procedure de rollback et validation pre-release documentees.
```

## 14. Risques principaux et mitigations

| Risque | Probabilite | Impact | Mitigation |
| --- | --- | --- | --- |
| Perte de donnees | Moyenne | Fort | Backup complet, dry-run, rollback teste |
| Migration partielle | Moyenne | Fort | Idempotence, transactions, controles post-migration |
| Incompatibilite v1/v2 | Elevee si breaking change | Fort | Tag majeur `v2.0.0`, changelog, PR explicite |
| Downtime superieur au prevu | Moyenne | Moyen/Fort | Chronometrage dry-run, fenetre maintenance, rollback rapide |
| Regression Logstash pipeline | Moyenne | Fort | Tests ingestion et comparaison index v1/v2 |
| Incompatibilite dashboards Kibana | Moyenne | Moyen | Export/import controle, validation manuelle |
| Drift configuration Docker | Moyenne | Moyen | `docker compose config`, revue des ports/volumes/reseaux |
| Rollback incomplet | Faible/Moyenne | Fort | Test rollback obligatoire avant production |
| Documentation insuffisante | Moyenne | Moyen | Rapport dans `docs/migrations/`, checklist delivery |

## 15. Critere de validation finale

La migration peut etre approuvee si :

- tous les tests critiques sont `OK`;
- la migration a ete executee en staging;
- le rollback a ete teste;
- les donnees critiques sont controlees;
- `CHANGELOG.md` est a jour;
- le rapport est complete;
- la PR est approuvee;
- le tag `v2.0.0` est cree apres merge.

Decision finale :

```text
Migration status: APPROVED / REJECTED / ROLLBACK REQUIRED
Validated by: <nom>
Date: 2026-06-23
```
