terraform {
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = ">= 3.0.2"
    }
  }
}

data "docker_network" "net" {
  name = var.network_name
}

resource "docker_volume" "redpanda_data" {
  name = "redpanda_data"
}

resource "docker_image" "redpanda" {
  name         = var.redpanda_image
  keep_locally = true
}

resource "docker_image" "console" {
  name         = var.console_image
  keep_locally = true
}

resource "docker_container" "redpanda" {
  name    = "redpanda"
  image   = docker_image.redpanda.image_id
  restart = "unless-stopped"

  # Kafka (host:19092) and Admin API (host:9644)
  ports {
    internal = var.kafka_port
    external = var.kafka_external_port
  }
  ports {
    internal = var.admin_port
    external = var.admin_port
  }

  networks_advanced { name = data.docker_network.net.name }

  mounts {
    target = "/var/lib/redpanda/data"
    source = docker_volume.redpanda_data.name
    type   = "volume"
  }

  healthcheck {
    # bash /dev/tcp works in most images; this only checks the port is listening.
    test         = ["CMD-SHELL", "bash -lc 'exec 3<>/dev/tcp/127.0.0.1/${var.admin_port}'"]
    interval     = "10s"
    timeout      = "3s"
    retries      = 10
    start_period = "20s"
  }

  # NOTE: No explicit --schema-registry-addr; default SR port 8081 stays internal-only.
  command = [
    "redpanda", "start",
    "--kafka-addr", "internal://0.0.0.0:${var.kafka_port},external://0.0.0.0:${var.kafka_external_port}",
    "--advertise-kafka-addr", "internal://redpanda:${var.kafka_port},external://localhost:${var.kafka_external_port}",
    "--rpc-addr", "redpanda:33145", "--advertise-rpc-addr", "redpanda:33145",
    "--mode", "dev-container", "--overprovisioned", "--smp", "1", "--memory", "1024M", "--reserve-memory", "0M", "--check=false"
  ]
}

resource "docker_container" "redpanda-console" {
  name    = "redpanda-console"
  image   = docker_image.console.image_id
  restart = "unless-stopped"

  # Console listens on 8080 inside the container; publish it to host var.console_port (default 8085)
  ports {
    internal = 8080
    external = var.console_port
  }
  healthcheck {
    # use curl if present, else wget; succeed on HTTP 200 from /
    test         = ["CMD-SHELL", "sh -lc '(command -v curl && curl -fsS http://127.0.0.1:8080/) || (command -v wget && wget -qO- http://127.0.0.1:8080/)'"]
    interval     = "10s"
    timeout      = "3s"
    retries      = 10
    start_period = "10s"
  }

  networks_advanced { name = data.docker_network.net.name }

  # Minimal config: point UI at Kafka broker; SR/Admin are optional
  env = [
    "KAFKA_BROKERS=redpanda:${var.kafka_port}"
  ]

  depends_on = [docker_container.redpanda]
}
