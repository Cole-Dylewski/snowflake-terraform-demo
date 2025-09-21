
# Volumes (ensure present)
resource "docker_volume" "airflow_dags"    { name = "airflow_dags" }
resource "docker_volume" "airflow_logs"    { name = "airflow_logs" }
resource "docker_volume" "airflow_plugins" { name = "airflow_plugins" }
