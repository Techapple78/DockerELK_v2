# DockerELK

Stack Elastic composee de trois services Docker :

- Elasticsearch
- Logstash
- Kibana

Le provisionnement des paquets est fait par Ansible pendant le build des images.

## Prerequis

- Docker
- Docker Compose v2+

## Structure

```text
Elastic/
  Dockerfile
  elastic.playbook.yml
  config/elasticsearch.yml
Kibana/
  Dockerfile
  kibana.playbook.yml
  config/kibana.yml
Logstash/
  Dockerfile
  logstash.playbook.yml
  config/logstash.yml
  pipeline/logstash.conf
docker-compose.yml
```

## Build

Depuis la racine du depot :

```console
docker compose build
```

Build cible :

```console
docker compose build elasticsearch
docker compose build logstash
docker compose build kibana
```

## Demarrage

```console
docker compose up
```

Mode detache :

```console
docker compose up -d
```

Kibana est disponible sur :

```text
http://localhost:5601
```

Elasticsearch est disponible sur :

```text
http://localhost:9200
```

## Ports

| Port | Service | Usage |
| --- | --- | --- |
| 5044 | Logstash | Beats / TCP input |
| 10514 | Logstash | Syslog TCP/UDP |
| 9200 | Elasticsearch | HTTP API |
| 9300 | Elasticsearch | Transport |
| 5601 | Kibana | Interface web |

## Tests de validation

```console
docker compose config
docker compose build elasticsearch
docker compose build logstash
docker compose build kibana
docker compose build
```

Tests rapides des entrypoints :

```console
docker run --rm dockerelk_elastic --version
docker run --rm dockerelk_logstash --version
docker run --rm dockerelk_kibana --version
```

## Demo infra Elasticsearch/Kibana

Une demo d'evenements infrastructure peut etre chargee dans Elasticsearch, puis visualisee dans Kibana.

Objets crees pendant la validation :

| Objet | ID / nom | Description |
| --- | --- | --- |
| Index template Elasticsearch | `infra-test-template` | Mapping et settings pour `infra-test-*` |
| Index Elasticsearch | `infra-test-2026.06.23` | 72 evenements infra synthetiques |
| Kibana index pattern | `infra-test` | Pattern `infra-test-*`, champ temps `@timestamp` |
| Kibana visualization | `infra-events-count` | Compteur total d'evenements |
| Kibana visualization | `infra-cpu-over-time` | Moyenne CPU dans le temps |
| Kibana visualization | `infra-severity-split` | Repartition des evenements par severite |
| Kibana dashboard | `infra-test-overview` | Dashboard `Infra Test Overview` |

Dashboard :

```text
http://localhost:5601/app/kibana#/dashboard/infra-test-overview
```

Verifier les donnees :

```powershell
(Invoke-WebRequest -UseBasicParsing `
  'http://localhost:9200/infra-test-2026.06.23/_count').Content
```

Verifier les objets Kibana :

```powershell
(Invoke-WebRequest -UseBasicParsing `
  'http://localhost:5601/api/saved_objects/dashboard/infra-test-overview' `
  -Headers @{ 'kbn-xsrf'='dockerelk' }).Content
```

Creer ou remplacer le template Elasticsearch :

```powershell
$template = @'
{
  "index_patterns": ["infra-test-*"],
  "settings": {
    "number_of_shards": 1,
    "number_of_replicas": 0
  },
  "mappings": {
    "doc": {
      "properties": {
        "@timestamp": { "type": "date" },
        "host": {
          "properties": {
            "name": { "type": "keyword" },
            "ip": { "type": "ip" },
            "environment": { "type": "keyword" },
            "role": { "type": "keyword" }
          }
        },
        "service": { "type": "keyword" },
        "event": {
          "properties": {
            "category": { "type": "keyword" },
            "severity": { "type": "keyword" },
            "message": { "type": "text" }
          }
        },
        "metrics": {
          "properties": {
            "cpu_percent": { "type": "float" },
            "memory_percent": { "type": "float" },
            "disk_percent": { "type": "float" },
            "network_in_kbps": { "type": "float" },
            "network_out_kbps": { "type": "float" },
            "response_time_ms": { "type": "float" }
          }
        }
      }
    }
  }
}
'@

Invoke-RestMethod -Method Put `
  -Uri 'http://localhost:9200/_template/infra-test-template' `
  -ContentType 'application/json' `
  -Body $template
```

Exemple d'evenement infra :

```powershell
$event = @'
{
  "@timestamp": "2026-06-23T12:00:00.000Z",
  "host": {
    "name": "web-01",
    "ip": "10.10.1.11",
    "environment": "prod",
    "role": "web"
  },
  "service": "nginx",
  "event": {
    "category": "infrastructure",
    "severity": "warn",
    "message": "Resource usage requires attention"
  },
  "metrics": {
    "cpu_percent": 82.4,
    "memory_percent": 74.2,
    "disk_percent": 61.8,
    "network_in_kbps": 1840,
    "network_out_kbps": 920,
    "response_time_ms": 138
  }
}
'@

Invoke-RestMethod -Method Post `
  -Uri 'http://localhost:9200/infra-test-2026.06.23/doc?refresh=true' `
  -ContentType 'application/json' `
  -Body $event
```

Nettoyer la demo :

```powershell
Invoke-RestMethod -Method Delete `
  -Uri 'http://localhost:9200/infra-test-*'

Invoke-RestMethod -Method Delete `
  -Uri 'http://localhost:9200/_template/infra-test-template'

Invoke-RestMethod -Method Delete `
  -Uri 'http://localhost:5601/api/saved_objects/dashboard/infra-test-overview' `
  -Headers @{ 'kbn-xsrf'='dockerelk' }

Invoke-RestMethod -Method Delete `
  -Uri 'http://localhost:5601/api/saved_objects/visualization/infra-events-count' `
  -Headers @{ 'kbn-xsrf'='dockerelk' }

Invoke-RestMethod -Method Delete `
  -Uri 'http://localhost:5601/api/saved_objects/visualization/infra-cpu-over-time' `
  -Headers @{ 'kbn-xsrf'='dockerelk' }

Invoke-RestMethod -Method Delete `
  -Uri 'http://localhost:5601/api/saved_objects/visualization/infra-severity-split' `
  -Headers @{ 'kbn-xsrf'='dockerelk' }

Invoke-RestMethod -Method Delete `
  -Uri 'http://localhost:5601/api/saved_objects/index-pattern/infra-test' `
  -Headers @{ 'kbn-xsrf'='dockerelk' }
```

## Logs de test

Exemple d'envoi vers Logstash :

```console
nc localhost 5044 < /path/to/logfile.log
```

Les evenements Logstash sont envoyes vers Elasticsearch via le hostname Docker :

```text
elasticsearch:9200
```

## Scalabilite horizontale

Les topologies suivantes sont des environnements de test paralleles. Elles utilisent des ports et des repertoires `.data-*` separes afin de ne pas ecraser la stack principale.

| Fichier Compose | Usage | Ports principaux |
| --- | --- | --- |
| `docker-compose.staging.yml` | Validation parallele simple avant prod | ES `19200`, Kibana `15601`, Logstash `15044` |
| `docker-compose.logstash-scale.yml` | Deux instances Logstash vers un Elasticsearch | ES `29200`, Kibana `25601`, Logstash `25044` et `25045` |
| `docker-compose.elasticsearch-cluster.yml` | Cluster Elasticsearch 3 noeuds + Logstash + Kibana | ES `39200`, Kibana `35601`, Logstash `35044` |
| `docker-compose.kibana-scale.yml` | Deux instances Kibana vers le meme Elasticsearch | ES `49200`, Kibana `45601` et `45602`, Logstash `45044` |

Commandes de validation :

```powershell
docker compose -f docker-compose.staging.yml config
docker compose -f docker-compose.staging.yml up -d --build
powershell -ExecutionPolicy Bypass -File tests\Smoke-Test.ps1 `
  -ElasticsearchUrl http://localhost:19200 `
  -KibanaUrl http://localhost:15601 `
  -LogstashPort 15044
```

Test d'ingestion :

```powershell
powershell -ExecutionPolicy Bypass -File tests\Send-TestEvent.ps1 `
  -Port 15044 `
  -Path /staging-smoke

powershell -ExecutionPolicy Bypass -File tests\Verify-Ingestion.ps1 `
  -ElasticsearchUrl http://localhost:19200 `
  -MinimumCount 1
```

Test Logstash horizontal :

```powershell
docker compose -f docker-compose.logstash-scale.yml up -d --build
powershell -ExecutionPolicy Bypass -File tests\Send-TestEvent.ps1 -Port 25044 -Path /logstash-a
powershell -ExecutionPolicy Bypass -File tests\Send-TestEvent.ps1 -Port 25045 -Path /logstash-b
powershell -ExecutionPolicy Bypass -File tests\Verify-Ingestion.ps1 `
  -ElasticsearchUrl http://localhost:29200 `
  -MinimumCount 2
```

Test cluster Elasticsearch :

```powershell
docker compose -f docker-compose.elasticsearch-cluster.yml up -d --build
powershell -ExecutionPolicy Bypass -File tests\Smoke-Test.ps1 `
  -ElasticsearchUrl http://localhost:39200 `
  -KibanaUrl http://localhost:35601 `
  -LogstashPort 35044
```

Dans ce scenario, `Elastic/config/elasticsearch-cluster.yml` desactive le seuil disque d'allocation des shards pour les tests locaux Docker Desktop. Ce reglage est utile en labo, mais il ne doit pas etre repris tel quel en production.

Test de tolerance a la perte d'un noeud :

```powershell
docker compose -f docker-compose.elasticsearch-cluster.yml stop es02
powershell -ExecutionPolicy Bypass -File tests\Send-TestEvent.ps1 `
  -Port 35044 `
  -Path /es-cluster-one-node-down
powershell -ExecutionPolicy Bypass -File tests\Verify-Ingestion.ps1 `
  -ElasticsearchUrl http://localhost:39200 `
  -MinimumCount 1
docker compose -f docker-compose.elasticsearch-cluster.yml start es02
```

Test Kibana horizontal :

```powershell
docker compose -f docker-compose.kibana-scale.yml up -d --build
powershell -ExecutionPolicy Bypass -File tests\Smoke-Test.ps1 `
  -ElasticsearchUrl http://localhost:49200 `
  -KibanaUrl http://localhost:45601 `
  -LogstashPort 45044
powershell -ExecutionPolicy Bypass -File tests\Smoke-Test.ps1 `
  -ElasticsearchUrl http://localhost:49200 `
  -KibanaUrl http://localhost:45602 `
  -LogstashPort 45044
```

Deploiement controle sur la stack principale :

```powershell
docker compose -f docker-compose.yml up -d --build
powershell -ExecutionPolicy Bypass -File tests\Smoke-Test.ps1 `
  -ElasticsearchUrl http://localhost:9200 `
  -KibanaUrl http://localhost:5601 `
  -LogstashPort 5044
powershell -ExecutionPolicy Bypass -File tests\Send-TestEvent.ps1 `
  -Port 5044 `
  -Path /prod-post-scale-validation
powershell -ExecutionPolicy Bypass -File tests\Verify-Ingestion.ps1 `
  -ElasticsearchUrl http://localhost:9200 `
  -MinimumCount 1
```

## Kubernetes sur vSphere

Le socle Terraform pour un cluster K3s de trois VMs avec IP statiques et
bootstrap Argo CD se trouve dans
[`infra/k3s-vsphere`](infra/k3s-vsphere/README.md).

Le compte rendu anonymise du deploiement, incluant les incidents et les etats
attendus, est disponible dans
[`docs/deploy/2026-06-24_k3s-vsphere-deployment-report.md`](docs/deploy/2026-06-24_k3s-vsphere-deployment-report.md).

Ce mode est actuellement une fondation d'infrastructure. Le deploiement ELK
Kubernetes est disponible dans `kubernetes/overlays/lab-k3s` avec ECK `3.4.0`
et Elastic Stack `9.4.2`.

Orchestration complete :

```powershell
powershell -ExecutionPolicy Bypass -File `
  infra\k3s-vsphere\scripts\Deploy-ElasticStack.ps1
```

La procedure cree egalement des donnees infrastructure synthetiques et le
dashboard `DockerELK Infrastructure Overview`.

Acces Kibana :

```powershell
powershell -ExecutionPolicy Bypass -File `
  infra\k3s-vsphere\scripts\Open-Kibana.ps1
```

Dashboard :

```text
https://localhost:5601/app/dashboards#/view/dockerelk-infra-overview
```

Le profil utilise un Elasticsearch mono-noeud et le stockage local K3s. Il est
destine au laboratoire et ne fournit pas de haute disponibilite des donnees.

## Notes

Cette stack utilise encore une base Ubuntu 16.04 et Elastic Stack 6.x. Ces versions sont anciennes et doivent faire l'objet d'une migration dediee avant un usage de production.
