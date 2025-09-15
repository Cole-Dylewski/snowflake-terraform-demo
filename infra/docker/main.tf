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
}

# Build FastAPI image (deps baked in, req_hash forces rebuild on changes)
resource "docker_image" "api" {
  name = "demo-fastapi:local"

  build {
    context    = local.app_dir
    dockerfile = "Dockerfile"

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

  env = [
    "DATABASE_URL_SRC=postgresql://${var.src_db_user}:${var.src_db_password}@src_db:5432/${var.src_db_name}",
    "DATABASE_URL_DST=postgresql://${var.dst_db_user}:${var.dst_db_password}@dst_db:5432/${var.dst_db_name}",
  ]

  depends_on = [
    docker_container.src_db,
    docker_container.dst_db
  ]

  ports {
    internal = 8000
    external = var.api_port
  }

  mounts {
    type   = "bind"
    source = abspath("${path.module}/../../app")
    target = "/app"
  }

  command = [
    "uvicorn", "main:app",
    "--host", "0.0.0.0",
    "--port", "8000",
    "--reload"
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
