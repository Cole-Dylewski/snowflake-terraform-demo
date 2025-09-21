output "airflow_web_url" {
  description = "Local URL for Airflow Web UI"
  value       = "http://localhost:${var.web_external_port}"
}
