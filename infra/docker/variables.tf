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
