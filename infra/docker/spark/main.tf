terraform {
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = ">= 3.0.0"
    }
  }
}

locals {
  cfg = {
    SPARK_WORKER_COUNT   = tonumber(try(var.env["SPARK_WORKER_COUNT"], "1"))
    SPARK_WORKER_CORES   = try(var.env["SPARK_WORKER_CORES"], "2")
    SPARK_WORKER_MEMORY  = try(var.env["SPARK_WORKER_MEMORY"], "2g")

    JUPYTER_TOKEN        = try(var.env["JUPYTER_TOKEN"], "dev")
    JUPYTER_PORT         = tonumber(try(var.env["JUPYTER_PORT"], "8889"))

    SPARK_MASTER_UI_PORT = tonumber(try(var.env["SPARK_MASTER_UI_PORT"], "9090"))
    SPARK_MASTER_PORT    = tonumber(try(var.env["SPARK_MASTER_PORT"], "7077"))
    SPARK_HISTORY_PORT   = tonumber(try(var.env["SPARK_HISTORY_PORT"], "18080"))
    SPARK_WORKER_UI_BASE = tonumber(try(var.env["SPARK_WORKER_UI_BASE"], "9091"))

    ENABLE_MINIO         = lower(try(var.env["ENABLE_MINIO"], "false")) == "true"
    MINIO_ROOT_USER      = try(var.env["MINIO_ROOT_USER"], "admin")
    MINIO_ROOT_PASSWORD  = try(var.env["MINIO_ROOT_PASSWORD"], "admin12345")
    MINIO_API_PORT       = tonumber(try(var.env["MINIO_API_PORT"], "9000"))
    MINIO_CONSOLE_PORT   = tonumber(try(var.env["MINIO_CONSOLE_PORT"], "9001"))
  }
}

# Reuse existing network by name

resource "docker_volume" "spark_events" {
  name = "spark_events"
}
resource "docker_volume" "spark_apps" {
  name = "spark_apps"
}
resource "docker_volume" "jupyter_home" {
  name = "jupyter_home"
}
resource "docker_volume" "minio_data" {
  name = "minio_data"
}

# Multi-arch images (works on Raspberry Pi)
resource "docker_image" "spark" {
  name = "bitnami/spark:3.5.1-debian-12-r8"
}
resource "docker_image" "jupyter" {
  name = "jupyter/pyspark-notebook:python-3.11"
}
resource "docker_image" "minio" {
  count = local.cfg.ENABLE_MINIO ? 1 : 0
  name  = "bitnami/minio:2024"
}

# Spark Master
resource "docker_container" "spark_master" {
  name  = "spark-master"
  image = docker_image.spark.image_id

  env = [
    "SPARK_MODE=master",
    "SPARK_MASTER_HOST=spark-master",
    "SPARK_LOG_LEVEL=INFO"
  ]

  ports {
    internal = local.cfg.SPARK_MASTER_PORT
    external = local.cfg.SPARK_MASTER_PORT
  }
  ports {
    internal = 8080
    external = local.cfg.SPARK_MASTER_UI_PORT
  }

  networks_advanced {
    name = var.network_name
  }

  mounts {
    target = "/opt/bitnami/spark/tmp/spark-events"
    type   = "volume"
    source = docker_volume.spark_events.name
  }
}

# Spark Workers
resource "docker_container" "spark_worker" {
  count = local.cfg.SPARK_WORKER_COUNT

  name  = format("spark-worker-%02d", count.index + 1)
  image = docker_image.spark.image_id

  env = [
    "SPARK_MODE=worker",
    "SPARK_MASTER_URL=spark://spark-master:${local.cfg.SPARK_MASTER_PORT}",
    "SPARK_WORKER_CORES=${local.cfg.SPARK_WORKER_CORES}",
    "SPARK_WORKER_MEMORY=${local.cfg.SPARK_WORKER_MEMORY}",
    "SPARK_LOG_LEVEL=INFO"
  ]

  # expose UI for the first worker only
  dynamic "ports" {
    for_each = count.index == 0 ? [1] : []
    content {
      internal = 8081
      external = local.cfg.SPARK_WORKER_UI_BASE
    }
  }

  networks_advanced {
    name = var.network_name
  }

  depends_on = [docker_container.spark_master]
}

# Spark History Server
resource "docker_container" "spark_history" {
  name  = "spark-history"
  image = docker_image.spark.image_id

  env = [
    "SPARK_MODE=history-server",
    "SPARK_HISTORY_OPTS=-Dspark.history.fs.logDirectory=/opt/bitnami/spark/tmp/spark-events -Dspark.history.ui.port=${local.cfg.SPARK_HISTORY_PORT}"
  ]

  ports {
    internal = local.cfg.SPARK_HISTORY_PORT
    external = local.cfg.SPARK_HISTORY_PORT
  }

  networks_advanced {
    name = var.network_name
  }

  mounts {
    target = "/opt/bitnami/spark/tmp/spark-events"
    type   = "volume"
    source = docker_volume.spark_events.name
  }

  depends_on = [docker_container.spark_master, docker_container.spark_worker]
}

# JupyterLab (PySpark)
resource "docker_container" "jupyter" {
  name  = "jupyterlab"
  image = docker_image.jupyter.image_id

  env = [
    "JUPYTER_TOKEN=${local.cfg.JUPYTER_TOKEN}",
    "SPARK_MASTER=spark://spark-master:${local.cfg.SPARK_MASTER_PORT}"
  ]

  ports {
    internal = 8888
    external = local.cfg.JUPYTER_PORT
  }

  networks_advanced {
    name = var.network_name
  }

  mounts {
    target = "/home/jovyan/work"
    type   = "volume"
    source = docker_volume.spark_apps.name
  }
  mounts {
    target = "/home/jovyan/.jupyter"
    type   = "volume"
    source = docker_volume.jupyter_home.name
  }

  command = ["start-notebook.sh"]

  depends_on = [docker_container.spark_master]
}

# Optional: MinIO
resource "docker_container" "minio" {
  count = local.cfg.ENABLE_MINIO ? 1 : 0

  name  = "minio"
  image = docker_image.minio[0].image_id

  env = [
    "MINIO_ROOT_USER=${local.cfg.MINIO_ROOT_USER}",
    "MINIO_ROOT_PASSWORD=${local.cfg.MINIO_ROOT_PASSWORD}"
  ]

  ports {
    internal = 9000
    external = local.cfg.MINIO_API_PORT
  }
  ports {
    internal = 9001
    external = local.cfg.MINIO_CONSOLE_PORT
  }

  networks_advanced {
    name = var.network_name
  }

  mounts {
    target = "/data"
    type   = "volume"
    source = docker_volume.minio_data.name
  }

  command = ["minio", "server", "/data", "--console-address=:9001"]
}
