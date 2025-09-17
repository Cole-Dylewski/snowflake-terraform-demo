variable "env" {
  description = "Map of env values (typically from .env)"
  type        = map(string)
  default     = {}
}

variable "network_name" {
  description = "Name of the existing Docker network to join"
  type        = string
  default     = "app_net"
}
