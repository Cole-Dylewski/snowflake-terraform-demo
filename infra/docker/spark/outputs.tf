output "spark_master_ui" {
  value = "http://localhost:${local.cfg.SPARK_MASTER_UI_PORT}"
}

output "spark_history_ui" {
  value = "http://localhost:${local.cfg.SPARK_HISTORY_PORT}"
}

output "spark_master_url" {
  value = "spark://localhost:${local.cfg.SPARK_MASTER_PORT}"
}

output "jupyter_url" {
  value     = "http://localhost:${local.cfg.JUPYTER_PORT}/?token=${local.cfg.JUPYTER_TOKEN}"
  sensitive = true
}

output "worker_1_ui" {
  value = "http://localhost:${local.cfg.SPARK_WORKER_UI_BASE}"
}

output "minio_console" {
  value     = local.cfg.ENABLE_MINIO ? "http://localhost:${local.cfg.MINIO_CONSOLE_PORT}" : null
  sensitive = false
}
