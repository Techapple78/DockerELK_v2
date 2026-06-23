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

## Notes

Cette stack utilise encore une base Ubuntu 16.04 et Elastic Stack 6.x. Ces versions sont anciennes et doivent faire l'objet d'une migration dediee avant un usage de production.
