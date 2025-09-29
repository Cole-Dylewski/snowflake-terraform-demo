############################################################
# Database (source / destination)
############################################################

variable "src_db_user" {
  description = "Username for the source Postgres DB."
  type        = string
  default     = "src_user"
  validation {
    condition     = length(var.src_db_user) > 0
    error_message = "src_db_user cannot be empty."
  }
}

variable "src_db_password" {
  description = "Password for the source Postgres DB."
  type        = string
  sensitive   = true
  default     = "src_pass"
  validation {
    condition     = length(var.src_db_password) > 0
    error_message = "src_db_password cannot be empty."
  }
}

variable "src_db_name" {
  description = "Database name for the source Postgres DB."
  type        = string
  default     = "src_db"
}

variable "dst_db_user" {
  description = "Username for the destination Postgres DB."
  type        = string
  default     = "dst_user"
  validation {
    condition     = length(var.dst_db_user) > 0
    error_message = "dst_db_user cannot be empty."
  }
}

variable "dst_db_password" {
  description = "Password for the destination Postgres DB."
  type        = string
  sensitive   = true
  default     = "dst_pass"
  validation {
    condition     = length(var.dst_db_password) > 0
    error_message = "dst_db_password cannot be empty."
  }
}

variable "dst_db_name" {
  description = "Database name for the destination Postgres DB."
  type        = string
  default     = "dst_db"
}

############################################################
# Host ports (validate 1..65535)
############################################################

variable "api_port" {
  description = "Host port for FastAPI service."
  type        = number
  default     = 8000
  validation {
    condition     = var.api_port >= 1 && var.api_port <= 65535
    error_message = "api_port must be between 1 and 65535."
  }
}

variable "src_host_port" {
  description = "Host port mapping to source Postgres."
  type        = number
  default     = 5433
  validation {
    condition     = var.src_host_port >= 1 && var.src_host_port <= 65535
    error_message = "src_host_port must be between 1 and 65535."
  }
}

variable "dst_host_port" {
  description = "Host port mapping to destination Postgres."
  type        = number
  default     = 5434
  validation {
    condition     = var.dst_host_port >= 1 && var.dst_host_port <= 65535
    error_message = "dst_host_port must be between 1 and 65535."
  }
}

variable "pgadmin_port" {
  description = "Host port for pgAdmin UI."
  type        = number
  default     = 8080
  validation {
    condition     = var.pgadmin_port >= 1 && var.pgadmin_port <= 65535
    error_message = "pgadmin_port must be between 1 and 65535."
  }
}

variable "http_port" {
  description = "Host port for Nginx (HTTP entry)."
  type        = number
  default     = 80
  validation {
    condition     = var.http_port >= 1 && var.http_port <= 65535
    error_message = "http_port must be between 1 and 65535."
  }
}

variable "pgweb_src_port" {
  description = "Host port for pgweb (source)."
  type        = number
  default     = 8081
  validation {
    condition     = var.pgweb_src_port >= 1 && var.pgweb_src_port <= 65535
    error_message = "pgweb_src_port must be between 1 and 65535."
  }
}

variable "pgweb_dst_port" {
  description = "Host port for pgweb (destination)."
  type        = number
  default     = 8082
  validation {
    condition     = var.pgweb_dst_port >= 1 && var.pgweb_dst_port <= 65535
    error_message = "pgweb_dst_port must be between 1 and 65535."
  }
}

# Kafka/Redpanda-related (used by outputs / console)
variable "console_port" {
  description = "Host port for Kafka console UI (if enabled)."
  type        = number
  default     = 8085
  validation {
    condition     = var.console_port >= 1 && var.console_port <= 65535
    error_message = "console_port must be between 1 and 65535."
  }
}

variable "admin_port" {
  description = "Host port for Redpanda Admin API (readiness/health)."
  type        = number
  default     = 9644
  validation {
    condition     = var.admin_port >= 1 && var.admin_port <= 65535
    error_message = "admin_port must be between 1 and 65535."
  }
}

############################################################
# Airflow admin & Fernet
############################################################

variable "airflow_fernet_key" {
  description = "Airflow Fernet key (base64 urlsafe). Generate once and keep secret."
  type        = string
  sensitive   = true
  # no default on purpose
  validation {
    condition     = length(var.airflow_fernet_key) > 0
    error_message = "airflow_fernet_key must be provided (no default)."
  }
}

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
  validation {
    condition     = length(var.airflow_admin_password) > 0
    error_message = "airflow_admin_password cannot be empty."
  }
}

variable "airflow_admin_email" {
  description = "Initial Airflow admin email."
  type        = string
  default     = "admin@example.com"
  validation {
    condition     = can(regex("@", var.airflow_admin_email))
    error_message = "airflow_admin_email must contain '@'."
  }
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

############################################################
# pgAdmin
############################################################

variable "pgadmin_email" {
  description = "pgAdmin login email."
  type        = string
  default     = "admin@example.com"
  validation {
    condition     = can(regex("@", var.pgadmin_email))
    error_message = "pgadmin_email must contain '@'."
  }
}

variable "pgadmin_password" {
  description = "pgAdmin login password."
  type        = string
  sensitive   = true
  default     = "admin"
  validation {
    condition     = length(var.pgadmin_password) > 0
    error_message = "pgadmin_password cannot be empty."
  }
}

############################################################
# Generic env map from .env
############################################################

variable "env" {
  description = "Key-value map from .env (used across modules)."
  type        = map(string)
  default     = {}
}

############################################################
# Spark / Airflow images (pinned) and versions
############################################################

variable "spark_version" {
  description = "Spark version for reference (should match image tag)."
  type        = string
  default     = "3.5.1"
}

variable "spark_image" {
  description = "Docker image for Spark (pin to tag or digest)."
  type        = string
  default     = "bitnami/spark:3.5.1"
}

variable "spark_master_host_port_ui" {
  description = "Host port for Spark Master Web UI/REST (maps to 8080 in container)."
  type        = number
  default     = 9090
  validation {
    condition     = var.spark_master_host_port_ui >= 1 && var.spark_master_host_port_ui <= 65535
    error_message = "spark_master_host_port_ui must be between 1 and 65535."
  }
}

variable "airflow_image" {
  description = "Docker image for Airflow Web/Scheduler (pin to tag or digest)."
  type        = string
  default     = "apache/airflow:2.9.2"
}

variable "jq_required_version" {
  description = "Required jq version on host (for scripts)."
  type        = string
  default     = "1.6"
}

############################################################
# MinIO (no defaults; must be provided)
############################################################

variable "MINIO_ROOT_USER" {
  description = "MinIO root user (required when MinIO is enabled)."
  type        = string
  sensitive   = true
  validation {
    condition     = length(var.MINIO_ROOT_USER) > 0
    error_message = "MINIO_ROOT_USER must be provided."
  }
}

variable "MINIO_ROOT_PASSWORD" {
  description = "MinIO root password (required when MinIO is enabled)."
  type        = string
  sensitive   = true
  validation {
    condition     = length(var.MINIO_ROOT_PASSWORD) >= 8
    error_message = "MINIO_ROOT_PASSWORD must be provided and at least 8 characters."
  }
}
