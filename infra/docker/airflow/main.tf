#############################
# Airflow Submodule (Docker)
#############################
# Inputs (from root module):
#   - var.network_name       : name of the Docker network to join (e.g., app_net)
#   - var.airflow_fernet_key : urlsafe base64 Fernet key for Airflow
# Optional:
#   - var.web_external_port  : host port mapped to container 8080 (default 8088)
terraform {
  required_providers {
    docker = {
      source = "kreuzwerker/docker"
    }
  }
}

variable "network_name" {
  description = "Existing Docker network name (e.g. app_net)"
  type        = string
}

variable "airflow_fernet_key" {
  description = "Airflow Fernet key (base64 urlsafe). Generate once and keep secret."
  type        = string
  sensitive   = true
}

variable "web_external_port" {
  description = "Host port for Airflow Web UI (container internal 8080)."
  type        = number
  default     = 8088
}

# Volumes
resource "docker_volume" "airflow_dags" { name = "airflow_dags" }
resource "docker_volume" "airflow_logs" { name = "airflow_logs" }
resource "docker_volume" "airflow_plugins" { name = "airflow_plugins" }

# Metadata DB
resource "docker_container" "airflow_db" {
  name  = "airflow_db"
  image = "postgres:16-alpine"

  env = [
    "POSTGRES_USER=airflow",
    "POSTGRES_PASSWORD=airflow",
    "POSTGRES_DB=airflow",
  ]

  networks_advanced {
    name = var.network_name
  }

  healthcheck {
    test     = ["CMD-SHELL", "pg_isready -U airflow -d airflow"]
    interval = "5s"
    timeout  = "3s"
    retries  = 20
  }
}

# Airflow image (with providers)
resource "docker_image" "airflow" {
  name = "snowflake-demo/airflow:2.10.4"
  build {
    context    = path.module
    dockerfile = "Dockerfile"
  }
}

# Shared env
locals {
  airflow_env = [
    "AIRFLOW__CORE__EXECUTOR=LocalExecutor",
    "AIRFLOW__CORE__LOAD_EXAMPLES=False",
    "AIRFLOW__DATABASE__SQL_ALCHEMY_CONN=postgresql+psycopg2://airflow:airflow@airflow_db:5432/airflow",
    "AIRFLOW__CORE__FERNET_KEY=${var.airflow_fernet_key}",
  ]
}

# Webserver
resource "docker_container" "airflow_web" {
  name  = "airflow_web"
  image = docker_image.airflow.name
  env   = local.airflow_env

  ports {
    internal = 8080
    external = var.web_external_port
  }

  volumes {
    volume_name    = docker_volume.airflow_dags.name
    container_path = "/opt/airflow/dags"
  }
  volumes {
    volume_name    = docker_volume.airflow_logs.name
    container_path = "/opt/airflow/logs"
  }
  volumes {
    volume_name    = docker_volume.airflow_plugins.name
    container_path = "/opt/airflow/plugins"
  }

  networks_advanced {
    name = var.network_name
  }

  depends_on = [docker_container.airflow_db]

  command = [
    "bash", "-lc",
    "airflow db migrate && airflow users create --username admin --password admin --firstname Cole --lastname D --role Admin --email you@example.com || true; exec airflow webserver"
  ]
}

# Scheduler
resource "docker_container" "airflow_scheduler" {
  name  = "airflow_scheduler"
  image = docker_image.airflow.name
  env   = local.airflow_env

  volumes {
    volume_name    = docker_volume.airflow_dags.name
    container_path = "/opt/airflow/dags"
  }
  volumes {
    volume_name    = docker_volume.airflow_logs.name
    container_path = "/opt/airflow/logs"
  }
  volumes {
    volume_name    = docker_volume.airflow_plugins.name
    container_path = "/opt/airflow/plugins"
  }

  networks_advanced {
    name = var.network_name
  }

  depends_on = [docker_container.airflow_db, docker_container.airflow_web]

  command = ["bash", "-lc", "exec airflow scheduler"]
}

# Triggerer
resource "docker_container" "airflow_triggerer" {
  name  = "airflow_triggerer"
  image = docker_image.airflow.name
  env   = local.airflow_env

  volumes {
    volume_name    = docker_volume.airflow_dags.name
    container_path = "/opt/airflow/dags"
  }
  volumes {
    volume_name    = docker_volume.airflow_logs.name
    container_path = "/opt/airflow/logs"
  }
  volumes {
    volume_name    = docker_volume.airflow_plugins.name
    container_path = "/opt/airflow/plugins"
  }

  networks_advanced {
    name = var.network_name
  }

  depends_on = [docker_container.airflow_db]

  command = ["bash", "-lc", "exec airflow triggerer"]
}

# Outputs
output "airflow_web_url" {
  description = "Local URL for Airflow Web UI"
  value       = "http://localhost:${var.web_external_port}"
}
