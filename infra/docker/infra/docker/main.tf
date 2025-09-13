terraform {
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0"
    }
  }
}

provider "docker" {}

resource "docker_network" "app_net" {
  name = "app_net"
}

resource "docker_volume" "src_db_data" { name = "src_db_data" }
resource "docker_volume" "dst_db_data" { name = "dst_db_data" }

data "docker_registry_image" "postgres" {
  name = "postgres:16"
}

resource "docker_image" "postgres" {
  name          = data.docker_registry_image.postgres.name
  pull_triggers = [data.docker_registry_image.postgres.sha256_digest]
}

resource "docker_container" "src_db" {
  name  = "src_db"
  image = docker_image.postgres.image_id

  networks_advanced { name = docker_network.app_net.name }

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
    source    = "${path.module}/db-init"
    read_only = true
  }

  restart = "always"
}

resource "docker_container" "dst_db" {
  name  = "dst_db"
  image = docker_image.postgres.image_id

  networks_advanced { name = docker_network.app_net.name }

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
    source    = "${path.module}/db-init"
    read_only = true
  }

  restart = "always"
}

resource "docker_image" "api" {
  name = "demo-fastapi:local"
  build {
    context    = "${path.module}/../../app"
    dockerfile = "Dockerfile"
  }
}

resource "docker_container" "api" {
  name  = "api"
  image = docker_image.api.image_id

  networks_advanced { name = docker_network.app_net.name }

  env = [
    "DATABASE_URL_SRC=postgresql://${var.src_db_user}:${var.src_db_password}@src_db:5432/${var.src_db_name}",
    "DATABASE_URL_DST=postgresql://${var.dst_db_user}:${var.dst_db_password}@dst_db:5432/${var.dst_db_name}",
  ]

  depends_on = [docker_container.src_db, docker_container.dst_db]

  ports {
    internal = 8000
    external = var.api_port
  }

  restart = "always"
}
