#/infra/docker/spark/main.tf

terraform {
  required_providers {
    docker = {
      source = "kreuzwerker/docker"
    }
  }
}

locals {
  # Parsed config (numbers via tonumber; booleans via string match)
  cfg = {
    SPARK_WORKER_COUNT  = tonumber(try(var.env["SPARK_WORKER_COUNT"], "1"))
    SPARK_WORKER_CORES  = try(var.env["SPARK_WORKER_CORES"], "2")
    SPARK_WORKER_MEMORY = try(var.env["SPARK_WORKER_MEMORY"], "2g")

    JUPYTER_TOKEN       = try(var.env["JUPYTER_TOKEN"], "dev")
    JUPYTER_PORT        = tonumber(try(var.env["JUPYTER_PORT"], "8889"))

    SPARK_MASTER_UI_PORT = tonumber(try(var.env["SPARK_MASTER_UI_PORT"], "9090"))
    SPARK_MASTER_PORT    = tonumber(try(var.env["SPARK_MASTER_PORT"], "7077"))
    SPARK_HISTORY_PORT   = tonumber(try(var.env["SPARK_HISTORY_PORT"], "18080"))
    SPARK_WORKER_UI_BASE = tonumber(try(var.env["SPARK_WORKER_UI_BASE"], "9091"))

    ENABLE_MINIO        = lower(try(var.env["ENABLE_MINIO"], "false")) == "true"
    MINIO_ROOT_USER     = try(var.env["MINIO_ROOT_USER"], "admin")
    MINIO_ROOT_PASSWORD = try(var.env["MINIO_ROOT_PASSWORD"], "admin12345")
    MINIO_API_PORT      = tonumber(try(var.env["MINIO_API_PORT"], "9000"))
    MINIO_CONSOLE_PORT  = tonumber(try(var.env["MINIO_CONSOLE_PORT"], "9001"))
  }
}

# Volumes
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

# Images
resource "docker_image" "spark" {
  # Docker Official Image (least likely to be restricted)
  name = "spark:3.5.6-java17-r"
}

resource "docker_image" "jupyter" {
  name = "jupyter/pyspark-notebook:python-3.11"
}

resource "docker_image" "minio" {
  count = local.cfg.ENABLE_MINIO ? 1 : 0
  name  = "minio/minio:latest"
}

# Spark Master
resource "docker_container" "spark_master" {
  name  = "spark-master"
  image = docker_image.spark.image_id

  env = [
    "SPARK_NO_DAEMONIZE=true",
  ]

  command = [
    "/opt/spark/sbin/start-master.sh",
    "-h", "spark-master",
    "-p", tostring(local.cfg.SPARK_MASTER_PORT),
    "--webui-port", tostring(local.cfg.SPARK_MASTER_UI_PORT) # 9090 by default
  ]

  ports {
    internal = local.cfg.SPARK_MASTER_PORT
    external = local.cfg.SPARK_MASTER_PORT
  }
  ports {
    # ⬇️ was 8080; must match the webui-port above
    internal = local.cfg.SPARK_MASTER_UI_PORT
    external = local.cfg.SPARK_MASTER_UI_PORT
  }

  networks_advanced {
    name = var.network_name
  }

  mounts {
    target = "/event-logs"
    type   = "volume"
    source = docker_volume.spark_events.name
  }
}


# Spark Workers (official image)
resource "docker_container" "spark_worker" {
  count = local.cfg.SPARK_WORKER_COUNT

  name  = format("spark-worker-%02d", count.index + 1)
  image = docker_image.spark.image_id

  env = [
    "SPARK_NO_DAEMONIZE=true",
  ]

  # Start worker and point at master; set cores/memory/UI port
  command = [
    "/opt/spark/sbin/start-worker.sh",
    "spark://spark-master:${local.cfg.SPARK_MASTER_PORT}",
    "--cores", tostring(local.cfg.SPARK_WORKER_CORES),
    "--memory", local.cfg.SPARK_WORKER_MEMORY,
    "--webui-port", "8081"
  ]

  # expose only the first worker's UI, like before
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

# Spark History Server (official image)
resource "docker_container" "spark_history" {
  name    = "spark-history"
  image   = docker_image.spark.image_id
  restart = "unless-stopped"
  user    = "0:0"

  env = [
    "SPARK_NO_DAEMONIZE=true",
    "SPARK_HISTORY_OPTS=-Dspark.history.fs.logDirectory=file:/event-logs -Dspark.history.ui.port=${local.cfg.SPARK_HISTORY_PORT}"
  ]

  # Start the history server; ensure the log dir exists/perm’d
  entrypoint = ["/bin/bash", "-lc"]
  command    = [
    "mkdir -p /event-logs && chown -R 1001:0 /event-logs || true && chmod 0777 /event-logs && exec /opt/spark/sbin/start-history-server.sh"
  ]

  ports {
    internal = local.cfg.SPARK_HISTORY_PORT
    external = local.cfg.SPARK_HISTORY_PORT
  }

  networks_advanced {
    name = var.network_name
  }

  mounts {
    target = "/event-logs"
    type   = "volume"
    source = docker_volume.spark_events.name
  }

  healthcheck {
    test         = ["CMD-SHELL", "bash -lc 'exec 3<>/dev/tcp/127.0.0.1/${local.cfg.SPARK_HISTORY_PORT}'"]
    interval     = "10s"
    timeout      = "3s"
    retries      = 10
    start_period = "10s"
  }

  depends_on = [docker_container.spark_master, docker_container.spark_worker]
}


# JupyterLab (PySpark) – writes event logs into the same volume
resource "docker_container" "jupyter" {
  name  = "jupyterlab"
  image = docker_image.jupyter.image_id

  env = [
    "JUPYTER_TOKEN=${local.cfg.JUPYTER_TOKEN}",
    "SPARK_MASTER=spark://spark-master:${local.cfg.SPARK_MASTER_PORT}",
    "PYSPARK_SUBMIT_ARGS=--conf spark.eventLog.enabled=true --conf spark.eventLog.dir=file:/event-logs pyspark-shell",
    "NB_UID=1001",
    "NB_GID=0"
  ]

  ports {
    internal = 8888
    external = local.cfg.JUPYTER_PORT
  }

  networks_advanced {
    name = var.network_name
  }

  mounts {
    target = "/event-logs"
    type   = "volume"
    source = docker_volume.spark_events.name
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

  mounts {
    type      = "bind"
    source    = abspath("${path.root}/../../requirements-jupyter.txt")
    target    = "/tmp/requirements.txt"
    read_only = true
  }

  command = [
    "bash", "-lc",
    "if [ -f /tmp/requirements.txt ]; then pip install -r /tmp/requirements.txt; fi; exec start-notebook.sh"
  ]

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
