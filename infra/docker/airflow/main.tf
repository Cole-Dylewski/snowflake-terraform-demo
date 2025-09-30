########################################
# Volumes (shared across Airflow services)
########################################
resource "docker_volume" "airflow_logs"    { name = "airflow_logs" }
resource "docker_volume" "airflow_plugins" { name = "airflow_plugins" }

########################################
# Shared locals (versions + env)
########################################
locals {
  airflow_version = "3.1.0"
  python_minor    = "3.13"
  airflow_constraints_url = "https://raw.githubusercontent.com/apache/airflow/constraints-${local.airflow_version}/constraints-${local.python_minor}.txt"

  airflow_env = [
    "AIRFLOW__CORE__EXECUTOR=LocalExecutor",
    "AIRFLOW__CORE__LOAD_EXAMPLES=False",
    "AIRFLOW__DATABASE__SQL_ALCHEMY_CONN=postgresql+psycopg2://airflow:airflow@airflow_db:5432/airflow",
    "AIRFLOW__CORE__FERNET_KEY=${var.airflow_fernet_key}",
    "AIRFLOW__CORE__DAGS_FOLDER=/opt/airflow/dags",

    # Ensure web binds correctly even without CLI flags
    "AIRFLOW__WEBSERVER__WEB_SERVER_HOST=0.0.0.0",
    "AIRFLOW__WEBSERVER__WEB_SERVER_PORT=8080",
    # Airflow 3.x: API server bind (replaces webserver bind)
    "AIRFLOW__API__HOST=0.0.0.0",
    "AIRFLOW__API__PORT=8080",

    
    # Admin bootstrap
    "AIRFLOW_ADMIN_USERNAME=${var.airflow_admin_username}",
    "AIRFLOW_ADMIN_PASSWORD=${var.airflow_admin_password}",
    "AIRFLOW_ADMIN_EMAIL=${var.airflow_admin_email}",
    "AIRFLOW_ADMIN_FIRSTNAME=${var.airflow_admin_firstname}",
    "AIRFLOW_ADMIN_LASTNAME=${var.airflow_admin_lastname}",

    # Provider pinning via constraints
    "AIRFLOW_VERSION=${local.airflow_version}",
    "PYTHON_MINOR=${local.python_minor}",
    "AIRFLOW_CONSTRAINTS_URL=${local.airflow_constraints_url}",

    # QoL
    "PIP_DISABLE_PIP_VERSION_CHECK=1",
    "PYTHONDONTWRITEBYTECODE=1",
    "PYTHONUNBUFFERED=1",
  ]
}

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

  networks_advanced { name = var.network_name }

  healthcheck {
    test     = ["CMD-SHELL", "pg_isready -U airflow -d airflow"]
    interval = "5s"
    timeout  = "3s"
    retries  = 40
  }

  restart = "always"
}

########################################
# Webserver
########################################
resource "docker_container" "airflow_web" {
  name  = "airflow_web"
  image = "apache/airflow:${local.airflow_version}-python${local.python_minor}"
  env = concat(local.airflow_env, [
    "AIRFLOW__CORE__SIMPLE_AUTH_MANAGER_ALL_ADMINS=True"
  ])

  networks_advanced { name = var.network_name }

  ports {
    internal = 8080
    external = var.web_external_port
    ip       = "0.0.0.0"
  }

  # Mount requirements + DAGs
  volumes {
    host_path      = abspath("${path.module}/requirements.txt")
    container_path = "/opt/airflow/requirements.txt"
    read_only      = true
  }
  volumes {
    host_path      = abspath("${path.module}/../../../dags")
    container_path = "/opt/airflow/dags"
    read_only      = false
  }

  # Named volumes
  volumes {
    volume_name    = docker_volume.airflow_logs.name
    container_path = "/opt/airflow/logs"
  }
  volumes {
    volume_name    = docker_volume.airflow_plugins.name
    container_path = "/opt/airflow/plugins"
  }

  depends_on = [docker_container.airflow_db]

  # airflow_web command: wait for DB, install providers with constraints, migrate, start web
  command = [
    "bash", "-lc", <<-EOT
      set -e
      until pg_isready -h airflow_db -U airflow -d airflow -t 3; do sleep 1; done
      if [ -f /opt/airflow/requirements.txt ]; then
        pip install --no-cache-dir -r /opt/airflow/requirements.txt -c "$AIRFLOW_CONSTRAINTS_URL"
      fi
      airflow db migrate
      # NOTE: users CLI removed in Airflow 3 unless FAB auth manager is enabled.
      # Start the API server (replaces `airflow webserver` in 3.x)
      exec airflow api-server --host 0.0.0.0 --port 8080
    EOT
  ]

    healthcheck {
    test         = ["CMD-SHELL", "curl -sf http://localhost:8080/health || curl -sf http://localhost:8080/api/health || exit 1"]
    interval     = "10s"
    timeout      = "5s"
    retries      = "30"
    start_period = "90s"
  }


  restart = "always"
}

########################################
# Scheduler
########################################
resource "docker_container" "airflow_scheduler" {
  name  = "airflow_scheduler"
  image = "apache/airflow:${local.airflow_version}-python${local.python_minor}"
  env   = local.airflow_env

  networks_advanced { name = var.network_name }

  volumes {
    host_path      = abspath("${path.module}/../../../dags")
    container_path = "/opt/airflow/dags"
    read_only      = false
  }
  volumes {
    host_path      = abspath("${path.module}/requirements.txt")
    container_path = "/opt/airflow/requirements.txt"
    read_only      = true
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

  command = [
    "bash", "-lc", <<-EOT
      set -e
      if [ -f /opt/airflow/requirements.txt ]; then
        pip install --no-cache-dir -r /opt/airflow/requirements.txt -c "$AIRFLOW_CONSTRAINTS_URL"
      fi
      exec airflow scheduler
    EOT
  ]

  restart = "always"
}
resource "docker_container" "airflow_dag_processor" {
  name  = "airflow_dag_processor"
  image = "apache/airflow:${local.airflow_version}-python${local.python_minor}"
  env   = local.airflow_env
  networks_advanced { name = var.network_name }

  volumes {
    host_path      = abspath("${path.module}/../../../dags")
    container_path = "/opt/airflow/dags"
    read_only      = false
  }
  volumes {
    host_path      = abspath("${path.module}/requirements.txt")
    container_path = "/opt/airflow/requirements.txt"
    read_only      = true
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

  command = [
    "bash", "-lc", <<-EOT
      set -e
      if [ -f /opt/airflow/requirements.txt ]; then
        pip install --no-cache-dir -r /opt/airflow/requirements.txt -c "$AIRFLOW_CONSTRAINTS_URL"
      fi
      exec airflow dag-processor
    EOT
  ]

  restart = "always"
}


########################################
# Triggerer
########################################
resource "docker_container" "airflow_triggerer" {
  name  = "airflow_triggerer"
  image = "apache/airflow:${local.airflow_version}-python${local.python_minor}"
  env   = local.airflow_env

  networks_advanced { name = var.network_name }

  volumes {
    host_path      = abspath("${path.module}/requirements.txt")
    container_path = "/opt/airflow/requirements.txt"
    read_only      = true
  }
  volumes {
    host_path      = abspath("${path.module}/../../../dags")
    container_path = "/opt/airflow/dags"
    read_only      = false
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

  command = [
    "bash", "-lc", <<-EOT
      set -e
      if [ -f /opt/airflow/requirements.txt ]; then
        pip install --no-cache-dir -r /opt/airflow/requirements.txt -c "$AIRFLOW_CONSTRAINTS_URL"
      fi
      exec airflow triggerer
    EOT
  ]

  restart = "always"
}
