variable "network_name" {
  description = "Existing Docker network name (e.g. app_net)"
  type        = string
}

variable "airflow_fernet_key" {
  description = "Airflow Fernet key (base64 urlsafe)."
  type        = string
  sensitive   = true
}

variable "web_external_port" {
  description = "Host port for Airflow Web UI (container internal 8080)."
  type        = number
  default     = 8088
}

variable "airflow_admin_username" {
  description = "Initial Airflow admin username."
  default = "admin"
  type        = string
}

variable "airflow_admin_password" {
  description = "Initial Airflow admin password."
  type        = string
  default = "admin"
  sensitive   = true
}

variable "airflow_admin_email" {
  description = "Initial Airflow admin email."
  default = "admin@example"
  type        = string
}

variable "airflow_admin_firstname" {
  description = "Initial Airflow admin first name."
  default = "Admin"
  type        = string
}

variable "airflow_admin_lastname" {
  description = "Initial Airflow admin last name."
  default = "User"
  type        = string
}
