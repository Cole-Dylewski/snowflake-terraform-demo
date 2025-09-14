output "app_url" { value = "http://localhost/" }
output "src_ui" { value = "http://localhost/src/" }
output "dest_ui" { value = "http://localhost/dest/" }
output "pgadmin_ui" { value = "http://localhost/pg/" }

output "src_psql" { value = "psql -h localhost -p ${var.src_host_port} -U ${var.src_db_user} ${var.src_db_name}" }
output "dst_psql" { value = "psql -h localhost -p ${var.dst_host_port} -U ${var.dst_db_user} ${var.dst_db_name}" }
