# Snowflake Terraform Demo

This project spins up a mock environment with:

* **Source & Destination PostgreSQL** databases
* **FastAPI app** (with optional hot reload for development)
* **pgAdmin** (database admin UI)
* **pgweb** (simple DB web UIs)
* **Nginx reverse proxy** (routes everything on port 80)

---

## Terraform Commands

Terraform manages all the containers, volumes, and networks defined in `infra/docker/*.tf`.

### 🔹 Initialize (one-time setup)

Download the required providers (Docker in this case).

```bash
terraform -chdir=infra/docker init
```

### 🔹 Plan (dry-run)

See what Terraform will create, change, or destroy without making changes.

```bash
terraform -chdir=infra/docker plan
```

### 🔹 Apply (create / update)

Actually build the environment based on your `.tf` files.

```bash
terraform -chdir=infra/docker apply
# or skip confirmation
terraform -chdir=infra/docker apply -auto-approve
```

### 🔹 Check Outputs

Show any handy connection commands or URLs defined in `outputs.tf`.

```bash
terraform -chdir=infra/docker output
```

### 🔹 Inspect Running Services

Standard Docker commands still work:

```bash
docker ps
docker logs api --tail=100
docker logs nginx --tail=100
```

### 🔹 Destroy

Tear down the entire environment and free resources.

```bash
terraform -chdir=infra/docker destroy
# or skip confirmation
terraform -chdir=infra/docker destroy -auto-approve
```

---

## Quick Test

After applying, you should be able to hit:

* FastAPI root → [http://localhost/](http://localhost/) → `{"message": "Hello, World!"}`
* Health check → [http://localhost/healthz](http://localhost/healthz)
* pgAdmin UI → [http://localhost/pg/](http://localhost/pg/)
* pgweb (source) → [http://localhost/src/](http://localhost/src/)
* pgweb (destination) → [http://localhost/dest/](http://localhost/dest/)

---

## Development Mode (FastAPI Hot Reload)

For local development, the FastAPI container is configured with:

* A bind mount from your local `app/` folder → `/app` inside the container.
* `uvicorn main:app --reload` so code changes trigger auto-restart.

This means you can edit files under `app/` and simply refresh your browser — no rebuild required.

⚠️ If file changes do not trigger reloads, increase inotify watch limits:

```bash
echo fs.inotify.max_user_watches=524288 | sudo tee -a /etc/sysctl.conf
echo fs.inotify.max_user_instances=1024 | sudo tee -a /etc/sysctl.conf
sudo sysctl -p
```
