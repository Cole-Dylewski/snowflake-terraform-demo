output "app_url" {
  value = var.http_port == 80 ? "http://localhost/" : "http://localhost:${var.http_port}/"
}

# Port-based URLs (replace old /src, /dest, /pg paths)
output "pgweb_src_url" {
  value = "http://localhost:${var.pgweb_src_port}"
}

output "pgweb_dst_url" {
  value = "http://localhost:${var.pgweb_dst_port}"
}

output "pgadmin_url" {
  value = "http://localhost:${var.pgadmin_port}"
}

# Helpful extras
output "redpanda_console_url" {
  value = "http://localhost:${var.console_port}"
}

output "redpanda_admin_url" {
  value = "http://localhost:${var.admin_port}"
}
