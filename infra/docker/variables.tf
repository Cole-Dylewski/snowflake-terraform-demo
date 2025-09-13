variable "src_db_user"     { type = string  default = "src_user" }
variable "src_db_password" { type = string  default = "src_pass" }
variable "src_db_name"     { type = string  default = "src_db" }

variable "dst_db_user"     { type = string  default = "dst_user" }
variable "dst_db_password" { type = string  default = "dst_pass" }
variable "dst_db_name"     { type = string  default = "dst_db" }

variable "api_port"        { type = number  default = 8000 }
variable "src_host_port"   { type = number  default = 5433 }
variable "dst_host_port"   { type = number  default = 5434 }
