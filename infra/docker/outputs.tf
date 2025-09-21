# Consolidated local endpoints for the dev stack
output "service_urls" {
  description = "Local endpoints for the dev stack (adjust as you change mappings)."
  value = {
    nginx         = "http://localhost" # reverse-proxies FastAPI
    api_via_nginx = "http://localhost" # same as nginx (public entry)

    pgadmin   = "http://localhost:8080"
    pgweb_src = "http://localhost:8081"
    pgweb_dst = "http://localhost:8082"

    spark_master_ui  = "http://localhost:9090"
    spark_worker_ui  = "http://localhost:9091"
    spark_history_ui = "http://localhost:18080"
    jupyterlab       = "http://localhost:8889"

    # Airflow web is dynamic (comes from the submodule; defaults to 8088 unless you changed it)
    airflow_web = module.airflow.airflow_web_url

    # Redpanda
    redpanda_readiness = "http://localhost:9644/v1/status/ready"
    kafka_bootstrap    = "localhost:9092" # if exposed; OK to ignore if you didn’t map it

    # Optional: if you run a DB proxy in this project, uncomment these:
    # db_proxy_src      = "localhost:6432"
    # db_proxy_dst      = "localhost:6433"
  }
}

# Convenience flat outputs (handy for copy/paste)
output "airflow_web_url" {
  description = "Airflow Web UI (from module)"
  value       = module.airflow.airflow_web_url
}
