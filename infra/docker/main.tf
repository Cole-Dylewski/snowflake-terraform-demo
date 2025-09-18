terraform {
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0"
    }
  }
}

provider "docker" {}

# Network & volumes
resource "docker_network" "app_net" {
  name = "app_net"
}

resource "docker_volume" "src_db_data" {
  name = "src_db_data"
}

resource "docker_volume" "dst_db_data" {
  name = "dst_db_data"
}

# Postgres image
data "docker_registry_image" "postgres" {
  name = "postgres:16"
}
resource "docker_image" "postgres" {
  name          = data.docker_registry_image.postgres.name
  pull_triggers = [data.docker_registry_image.postgres.sha256_digest]
}

# Source DB
resource "docker_container" "src_db" {
  name  = "src_db"
  image = docker_image.postgres.image_id

  networks_advanced {
    name = docker_network.app_net.name
  }

  env = [
    "POSTGRES_USER=${var.src_db_user}",
    "POSTGRES_PASSWORD=${var.src_db_password}",
    "POSTGRES_DB=${var.src_db_name}",
  ]

  ports {
    internal = 5432
    external = var.src_host_port
  }

  mounts {
    target = "/var/lib/postgresql/data"
    type   = "volume"
    source = docker_volume.src_db_data.name
  }

  mounts {
    target    = "/docker-entrypoint-initdb.d"
    type      = "bind"
    source    = abspath("${path.module}/db-init")
    read_only = true
  }

  restart = "always"
}

# Destination DB
resource "docker_container" "dst_db" {
  name  = "dst_db"
  image = docker_image.postgres.image_id

  networks_advanced {
    name = docker_network.app_net.name
  }

  env = [
    "POSTGRES_USER=${var.dst_db_user}",
    "POSTGRES_PASSWORD=${var.dst_db_password}",
    "POSTGRES_DB=${var.dst_db_name}",
  ]

  ports {
    internal = 5432
    external = var.dst_host_port
  }

  mounts {
    target = "/var/lib/postgresql/data"
    type   = "volume"
    source = docker_volume.dst_db_data.name
  }

  mounts {
    target    = "/docker-entrypoint-initdb.d"
    type      = "bind"
    source    = abspath("${path.module}/db-init")
    read_only = true
  }

  restart = "always"
}

locals {
  app_dir    = abspath("${path.module}/../../app")
  req_hash   = filesha256("${local.app_dir}/requirements.txt")
  dockerfile = "${local.app_dir}/Dockerfile"
  repo_root  = abspath("${path.module}/../..") # NEW
}

# Build FastAPI image (deps baked in, req_hash forces rebuild on changes)
resource "docker_image" "api" {
  name = "demo-fastapi:local"

  build {
    context    = local.repo_root  # CHANGED: was local.app_dir
    dockerfile = "app/Dockerfile" # CHANGED: path is relative to context
    build_args = {
      REQ_HASH = local.req_hash
    }
  }
}
# FastAPI container (HOT RELOAD)
resource "docker_container" "api" {
  name  = "api"
  image = docker_image.api.image_id

  networks_advanced {
    name = docker_network.app_net.name
  }

  ports {
    internal = 8000
    external = var.api_port
  }

  # Bind mounts: app/ and _utils/ at repo root (no TF var needed)
  mounts {
    type      = "bind"
    source    = abspath("${path.module}/../../app")
    target    = "/app"
    read_only = false
  }
  mounts {
    type      = "bind"
    source    = abspath("${path.module}/../../_utils")
    target    = "/ext/_utils"
    read_only = false
  }

  # Single env block (merge your DB URLs + PYTHONPATH)
  # CHANGED: PYTHONPATH so Python finds /ext_utils as a package under /ext
  env = [
    "DATABASE_URL_SRC=postgresql://${var.src_db_user}:${var.src_db_password}@src_db:5432/${var.src_db_name}",
    "DATABASE_URL_DST=postgresql://${var.dst_db_user}:${var.dst_db_password}@dst_db:5432/${var.dst_db_name}",
    "PYTHONPATH=/ext:/app"
  ]

  # CHANGED: drop the pip install; keep reload watching both dirs
  command = [
    "bash", "-lc",
    "uvicorn main:app --host 0.0.0.0 --port 8000 --reload --reload-dir /app --reload-dir /ext/_utils"
  ]

  depends_on = [
    docker_container.src_db,
    docker_container.dst_db
  ]

  restart = "always"
}



# pgAdmin UI
resource "docker_container" "pgadmin" {
  name  = "pgadmin"
  image = "dpage/pgadmin4:8"

  networks_advanced {
    name = docker_network.app_net.name
  }

  env = [
    "PGADMIN_DEFAULT_EMAIL=${var.pgadmin_email}",
    "PGADMIN_DEFAULT_PASSWORD=${var.pgadmin_password}",
  ]

  ports {
    internal = 80
    external = var.pgadmin_port
  }

  restart = "always"
}

# pgweb (source)
resource "docker_container" "pgweb_src" {
  name  = "pgweb_src"
  image = "sosedoff/pgweb:latest"

  networks_advanced {
    name = docker_network.app_net.name
  }

  ports {
    internal = 8081
    external = var.pgweb_src_port
  }

  command = [
    "--bind=0.0.0.0",
    "--listen=8081",
    "--url=postgres://${var.src_db_user}:${var.src_db_password}@src_db:5432/${var.src_db_name}?sslmode=disable"
  ]

  restart = "always"
}

# pgweb (destination)
resource "docker_container" "pgweb_dst" {
  name  = "pgweb_dst"
  image = "sosedoff/pgweb:latest"

  networks_advanced {
    name = docker_network.app_net.name
  }

  ports {
    internal = 8081
    external = var.pgweb_dst_port
  }

  command = [
    "--bind=0.0.0.0",
    "--listen=8081",
    "--url=postgres://${var.dst_db_user}:${var.dst_db_password}@dst_db:5432/${var.dst_db_name}?sslmode=disable"
  ]

  restart = "always"
}

# nginx image
data "docker_registry_image" "nginx" {
  name = "nginx:alpine"
}
resource "docker_image" "nginx" {
  name          = data.docker_registry_image.nginx.name
  pull_triggers = [data.docker_registry_image.nginx.sha256_digest]
}

# nginx container
resource "docker_container" "nginx" {
  name  = "nginx"
  image = docker_image.nginx.image_id

  networks_advanced {
    name = docker_network.app_net.name
  }

  ports {
    internal = 80
    external = var.http_port
    ip       = "0.0.0.0"
  }
  ports {
    internal = 443
    external = 443
    ip       = "0.0.0.0"
  }
  ports {
    internal = 80
    external = var.http_port
    ip       = "::"
  }
  ports {
    internal = 443
    external = 443
    ip       = "::"
  }

  mounts {
    type      = "bind"
    source    = abspath("${path.module}/nginx/nginx.conf")
    target    = "/etc/nginx/nginx.conf"
    read_only = true
  }

  mounts {
    type      = "bind"
    source    = abspath("${path.module}/nginx/certs")
    target    = "/etc/nginx/certs"
    read_only = true
  }

  depends_on = [
    docker_container.api,
    docker_container.pgweb_src,
    docker_container.pgweb_dst,
    docker_container.pgadmin
  ]

  restart = "always"
}


module "spark_cluster" {
  source       = "./spark"
  network_name = docker_network.app_net.name

  # Reuse the same Docker network as the rest of the stack

  # Plumb through .env via a map (use your existing pattern if you already load env)
  env = {
    SPARK_WORKER_COUNT  = try(var.env["SPARK_WORKER_COUNT"], "1")
    SPARK_WORKER_CORES  = try(var.env["SPARK_WORKER_CORES"], "2")
    SPARK_WORKER_MEMORY = try(var.env["SPARK_WORKER_MEMORY"], "2g")

    JUPYTER_TOKEN = try(var.env["JUPYTER_TOKEN"], "dev")
    JUPYTER_PORT  = try(var.env["JUPYTER_PORT"], "8889")

    SPARK_MASTER_UI_PORT = try(var.env["SPARK_MASTER_UI_PORT"], "9090")
    SPARK_MASTER_PORT    = try(var.env["SPARK_MASTER_PORT"], "7077")
    SPARK_HISTORY_PORT   = try(var.env["SPARK_HISTORY_PORT"], "18080")
    SPARK_WORKER_UI_BASE = try(var.env["SPARK_WORKER_UI_BASE"], "9091")

    ENABLE_MINIO        = try(var.env["ENABLE_MINIO"], "false")
    MINIO_ROOT_USER     = try(var.env["MINIO_ROOT_USER"], "admin")
    MINIO_ROOT_PASSWORD = try(var.env["MINIO_ROOT_PASSWORD"], "admin12345")
    MINIO_API_PORT      = try(var.env["MINIO_API_PORT"], "9000")
    MINIO_CONSOLE_PORT  = try(var.env["MINIO_CONSOLE_PORT"], "9001")
  }
}
