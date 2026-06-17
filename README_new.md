# Kibana — DockerELK

Composant **Kibana** du stack ELK dockerisé. Ce module déploie Kibana **6.3** via Ansible dans un conteneur Ubuntu 16.04 et le connecte automatiquement à Elasticsearch.

---

## Structure du dossier

```
Kibana/
├── config/
│   └── kibana.yml             # Configuration de Kibana
├── Dockerfile                 # Image basée sur Ubuntu 16.04 + Ansible
├── kibana.playbook.yml        # Playbook Ansible d'installation
├── docker-entrypoint.sh       # Script d'entrée du conteneur
└── docker-entrypoint.yml      # Playbook Ansible de démarrage
```

---

## Construction de l'image

```bash
# Depuis la racine du repo (recommandé)
docker-compose build

# Ou uniquement l'image Kibana
cd Kibana
docker build -t dockerelk_kibana .
```

Le Dockerfile :
1. installe Ansible sur Ubuntu 16.04,
2. exécute `kibana.playbook.yml` pour installer Kibana depuis le repo officiel Elastic,
3. configure l'URL d'Elasticsearch (`http://elasticsearch:9200`),
4. expose le port 5601.

---

## Port exposé

| Port  | Usage                  |
|-------|------------------------|
| 5601  | Interface web Kibana   |

---

## Configuration (`config/kibana.yml`)

| Paramètre           | Valeur                          | Description                              |
|---------------------|---------------------------------|------------------------------------------|
| `server.name`       | `kibana`                        | Nom du serveur Kibana                    |
| `server.host`       | `0`                             | Écoute sur toutes les interfaces         |
| `elasticsearch.url` | `http://elasticsearch:9200`     | Connexion à Elasticsearch via le réseau Docker `elk` |

---

## Accéder à Kibana

Une fois le stack démarré :

```
http://localhost:5601
```

---

## Initialisation de l'index pattern

Après le premier démarrage, créer l'index pattern `logstash-*` :

**Via curl :**
```bash
curl -XPOST -D- 'http://localhost:5601/api/saved_objects/index-pattern' \
  -H 'Content-Type: application/json' \
  -H 'kbn-version: 6.3.0' \
  -d '{"attributes":{"title":"logstash-*","timeFieldName":"@timestamp"}}'
```

**Via l'interface web :**  
Management → Index Patterns → Create index pattern → `logstash-*` → champ de temps : `@timestamp`

---

## Dépendance

Kibana **dépend d'Elasticsearch** (`depends_on: Elastic` dans `docker-compose.yml`). S'assurer qu'Elasticsearch est bien démarré et accessible avant de lancer Kibana.

---

## Lien avec le stack complet

Consulter le [README principal](../README.md) pour démarrer l'ensemble du stack ELK.
