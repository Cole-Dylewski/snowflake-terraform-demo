# Airflow submodule (uses kreuzwerker/docker from versions.tf)

########################################
# Metadata DB (Postgres)
########################################
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
    retries  = 40
  }

  restart = "always"
}

########################################
# Volumes (shared across Airflow services)
########################################
resource "docker_volume" "airflow_dags"    { name = "airflow_dags" }
resource "docker_volume" "airflow_logs"    { name = "airflow_logs" }
resource "docker_volume" "airflow_plugins" { name = "airflow_plugins" }

########################################
# Shared environment
########################################
locals {
  airflow_env = [
    "AIRFLOW__CORE__EXECUTOR=LocalExecutor",
    "AIRFLOW__CORE__LOAD_EXAMPLES=False",
    "AIRFLOW__DATABASE__SQL_ALCHEMY_CONN=postgresql+psycopg2://airflow:airflow@airflow_db:5432/airflow",
    "AIRFLOW__CORE__FERNET_KEY=${var.airflow_fernet_key}",

    # pass admin bootstrap values (used by the webserver startup script)
    "AIRFLOW_ADMIN_USERNAME=${var.airflow_admin_username}",
    "AIRFLOW_ADMIN_PASSWORD=${var.airflow_admin_password}",
    "AIRFLOW_ADMIN_EMAIL=${var.airflow_admin_email}",
    "AIRFLOW_ADMIN_FIRSTNAME=${var.airflow_admin_firstname}",
    "AIRFLOW_ADMIN_LASTNAME=${var.airflow_admin_lastname}",
  ]
}

########################################
# Webserver
########################################
resource "docker_container" "airflow_web" {
  name  = "airflow_web"
  image = "apache/airflow:2.10.4-python3.11"
  env   = local.airflow_env

  networks_advanced {
    name = var.network_name
  }

  ports {
    internal = 8080
    external = var.web_external_port
    ip       = "0.0.0.0"
  }

  # Named volumes
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

  depends_on = [docker_container.airflow_db]

  # Use heredoc so Terraform doesn't choke on multi-line strings
      command = [
    "bash", "-lc", <<-EOT
      set -e
      airflow db migrate
      airflow users create \
        --username "$${AIRFLOW_ADMIN_USERNAME}" \
        --password "$${AIRFLOW_ADMIN_PASSWORD}" \
        --firstname "$${AIRFLOW_ADMIN_FIRSTNAME}" \
        --lastname  "$${AIRFLOW_ADMIN_LASTNAME}" \
        --role Admin \
        --email "$${AIRFLOW_ADMIN_EMAIL}" || true
      exec airflow webserver
    EOT
  ]



  restart = "always"
}

########################################
# Scheduler
########################################
resource "docker_container" "airflow_scheduler" {
  name  = "airflow_scheduler"
  image = "apache/airflow:2.10.4-python3.11"
  env   = local.airflow_env

  networks_advanced {
    name = var.network_name
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

  depends_on = [docker_container.airflow_db]

  command = ["bash", "-lc", "exec airflow scheduler"]
  restart = "always"
}

########################################
# Triggerer
########################################
resource "docker_container" "airflow_triggerer" {
  name  = "airflow_triggerer"
  image = "apache/airflow:2.10.4-python3.11"
  env   = local.airflow_env

  networks_advanced {
    name = var.network_name
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

  depends_on = [docker_container.airflow_db]

  command = ["bash", "-lc", "exec airflow triggerer"]
  restart = "always"
}
