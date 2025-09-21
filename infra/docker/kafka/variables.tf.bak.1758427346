variable "network_name" {
  type    = string
  default = "app_net"
}

variable "redpanda_image" {
  type    = string
  default = "docker.redpanda.com/redpandadata/redpanda:latest"
}

variable "console_image" {
  type    = string
  default = "docker.redpanda.com/redpandadata/console:latest"
}

variable "kafka_port" {
  type    = number
  default = 9092
}

variable "kafka_external_port" {
  type    = number
  default = 19092
}

# Container port for Schema Registry (we won't publish it to host)
variable "schema_registry_port" {
  type    = number
  default = 8081
}

variable "admin_port" {
  type    = number
  default = 9644
}

variable "console_port" {
  type    = number
  default = 8085
}
