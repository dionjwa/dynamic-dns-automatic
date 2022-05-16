variable "config" {
  type    = string
}

variable "datacenters" {
  type    = list(string)
  default = ["dc1"]
}

job "ddns-updater" {

  datacenters = var.datacenters

  group "ddns-updater" {

    network {
      mode = "bridge"
    }

    task "ddns-updater" {
      driver = "docker"

      config {
        // alternative
        // image = "qmcgaw/ddns-updater"
        image = "ghcr.io/qdm12/ddns-updater"

        mount {
          type = "volume"
          target = "/updater/data"
          source = "ddns-updater"
        }
      }

      env {
        CONFIG = "${var.config}"
      }
    }
  }
}
