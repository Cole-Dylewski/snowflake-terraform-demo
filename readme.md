# Snowflake Terraform Demo

This project is a **containerized demo environment** to practice Terraform + Docker orchestration with:

* Two PostgreSQL databases (mock **source** and **destination**)
* A FastAPI server to interact with them (health checks, counts, migration, upserts)
* Optional pgAdmin UI for database browsing

The project runs **entirely in containers** via Terraform and the [kreuzwerker/docker provider](https://registry.terraform.io/providers/kreuzwerker/docker/latest).

---

## 📂 Project Structure

```
snowflake-terraform-demo/
├── app/                 # FastAPI app (Dockerfile + main.py)
├── infra/
│   └── docker/          # Terraform files
│       ├── main.tf
│       ├── variables.tf
│       ├── outputs.tf
│       └── db-init/     # optional SQL seed files
```

---

## ⚡ Prerequisites

* Linux machine (Debian/Ubuntu/Raspberry Pi OS works)
* Installed:

  * [Docker](https://docs.docker.com/engine/install/)
  * [Terraform](https://developer.hashicorp.com/terraform/downloads)

---

## 🚀 Setup from Scratch

Clone and enter the repo:

```bash
git clone https://github.com/Cole-Dylewski/snowflake-terraform-demo.git
cd snowflake-terraform-demo
```

Make sure Docker is running:

```bash
sudo systemctl start docker
sudo systemctl enable docker
```

Initialize Terraform:

```bash
terraform -chdir=infra/docker init
```

Apply the stack (creates 2 DBs, API, and pgAdmin):

```bash
terraform -chdir=infra/docker apply -auto-approve
```

---

## 🐳 Containers Deployed

* **src\_db** → Postgres @ `localhost:5433`
* **dst\_db** → Postgres @ `localhost:5434`
* **api** → FastAPI server @ `localhost:8000`
* **pgadmin** → pgAdmin UI @ `localhost:8080`

---

## 🔎 Quick Tests

### API

```bash
curl http://localhost:8000/healthz
curl http://localhost:8000/counts
curl -X POST http://localhost:8000/transfer
curl http://localhost:8000/counts
curl -X POST http://localhost:8000/upsert -H 'content-type: application/json' -d '{"id":4,"name":"delta"}'
```

### PostgreSQL CLI

```bash
# Connect to source DB
psql -h localhost -p 5433 -U src_user src_db

# Connect to destination DB
psql -h localhost -p 5434 -U dst_user dst_db
```

(Default passwords: `src_pass` / `dst_pass`)

### pgAdmin UI

Open [http://localhost:8080](http://localhost:8080)
Login with:

* Email: `admin@example.com`
* Password: `admin`

Add servers manually:

* Host: `src_db`, Port: 5432, User: `src_user`, Pass: `src_pass`
* Host: `dst_db`, Port: 5432, User: `dst_user`, Pass: `dst_pass`

---

## ⚙️ Project Management

### Tear down

```bash
terraform -chdir=infra/docker destroy -auto-approve
```

### Format & validate configs

```bash
terraform -chdir=infra/docker fmt
terraform -chdir=infra/docker validate
```

### Inspect outputs

```bash
terraform -chdir=infra/docker output
```

---

## 📌 Notes

* `infra/docker/db-init/` can contain `.sql` files that will be auto-executed when Postgres starts.
* You can change ports, usernames, and passwords in `infra/docker/variables.tf`.
* pgAdmin is optional—disable by commenting out the `pgadmin` resource in `main.tf`.

---

## ✅ Next Steps

* Extend FastAPI with new endpoints (schema clone, advanced migration logic).
* Add CI/CD pipelines (lint, validate, build).
* Deploy the same stack on a remote host.
