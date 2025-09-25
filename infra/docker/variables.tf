#infra/docker/variables.tf

variable "src_db_user" {
  type    = string
  default = "src_user"
}

variable "src_db_password" {
  type    = string
  default = "src_pass"
}

variable "src_db_name" {
  type    = string
  default = "src_db"
}

variable "dst_db_user" {
  type    = string
  default = "dst_user"
}

variable "dst_db_password" {
  type    = string
  default = "dst_pass"
}

variable "dst_db_name" {
  type    = string
  default = "dst_db"
}

variable "api_port" {
  type    = number
  default = 8000
}

variable "src_host_port" {
  type    = number
  default = 5433
}

variable "dst_host_port" {
  type    = number
  default = 5434
}

variable "pgadmin_port" {
  type    = number
  default = 8080
}

variable "pgadmin_email" {
  type    = string
  default = "admin@example.com"
}

variable "pgadmin_password" {
  type    = string
  default = "admin"
}

variable "http_port" {
  type    = number
  default = 80
}

variable "pgweb_src_port" {
  type    = number
  default = 8081
}

variable "pgweb_dst_port" {
  type    = number
  default = 8082
}

# Kafka-related (used by outputs / console)
variable "console_port" {
  type    = number
  default = 8085
}

variable "admin_port" {
  type    = number
  default = 9644
}

# Spark/module env map
variable "env" {
  description = "Key-value map from .env"
  type        = map(string)
  default     = {}
}

variable "airflow_fernet_key" {
  description = "Airflow Fernet key (base64 urlsafe). Generate once and keep secret."
  type        = string
  sensitive   = true
}

# ---- Airflow admin credentials (single source of truth) ----
variable "airflow_admin_username" {
  description = "Initial Airflow admin username."
  type        = string
  default     = "admin"
}

variable "airflow_admin_password" {
  description = "Initial Airflow admin password."
  type        = string
  sensitive   = true
  default     = "admin"
}

variable "airflow_admin_email" {
  description = "Initial Airflow admin email."
  type        = string
  default     = "admin@example.com"
}

variable "airflow_admin_firstname" {
  description = "Initial Airflow admin first name."
  type        = string
  default     = "Admin"
}

variable "airflow_admin_lastname" {
  description = "Initial Airflow admin last name."
  type        = string
  default     = "User"
}


variable "MINIO_ROOT_USER"     { 
  type = string 
  }
variable "MINIO_ROOT_PASSWORD" { 
  type = string
  sensitive = true 
  }
