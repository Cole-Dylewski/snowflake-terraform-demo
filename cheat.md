## Architecture

```mermaid
flowchart LR
  Browser((Your Browser)) -- :80/443 --> Nginx[Nginx]
  Nginx -- reverse_proxy --> API[FastAPI (uvicorn)]
  API -- SQL --> SRC_DB[(Postgres: src_db)]
  API -- SQL --> DST_DB[(Postgres: dst_db)]

  Browser -- :8080 --> PGADMIN[pgAdmin]
  Browser -- :8081 --> PGWEB_SRC[pgweb (source)]
  Browser -- :8082 --> PGWEB_DST[pgweb (destination)]

  Browser -- :9090 --> SPARK_MASTER[Spark Master UI]
  Browser -- :9091 --> SPARK_WORKER[Spark Worker UI]
  Browser -- :18080 --> SPARK_HISTORY[Spark History Server]
  Browser -- :8889 --> JUPYTER[JupyterLab]

  subgraph Docker Network: app_net
    Nginx
    API
    SRC_DB
    DST_DB
    PGADMIN
    PGWEB_SRC
    PGWEB_DST
    SPARK_MASTER
    SPARK_WORKER
    SPARK_HISTORY
    JUPYTER
  end
```

* Containers communicate on an isolated Docker network **`app_net`**.
* Only **Nginx (80/443)**, **pgAdmin (8080)**, **pgweb-src (8081)**, **pgweb-dst (8082)**, **Spark Master (9090)**, **Spark Worker-1 (9091)**, **Spark History (18080)**, and **JupyterLab (8889)** are published to the host.

---

## Quick Start & Startup Instructions

### Quick Start

## Service URLs

* **FastAPI (via nginx)**: [http://localhost/](http://localhost/)

  * Health: [http://localhost/health](http://localhost/health)
* **pgAdmin**: [http://localhost:8080/](http://localhost:8080/)
* **pgweb (source)**: [http://localhost:8081/](http://localhost:8081/)
* **pgweb (destination)**: [http://localhost:8082/](http://localhost:8082/)
* **Spark Master**: [http://localhost:9090/](http://localhost:9090/)
* **Spark Worker-1**: [http://localhost:9091/](http://localhost:9091/)
* **Spark History**: [http://localhost:18080/](http://localhost:18080/)
* **JupyterLab**: [http://localhost:8889/](http://localhost:8889/)

**Direct Postgres** (from host):

* Source: `psql -h 127.0.0.1 -p 5433 -U src_user src_db`
* Destination: `psql -h 127.0.0.1 -p 5434 -U dst_user dst_db`
