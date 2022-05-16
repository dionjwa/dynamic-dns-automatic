consul {
  address = "localhost:8500"

  retry {
    enabled  = true
    attempts = 12
    backoff  = "250ms"
  }
}

// It's very difficult to get the right templates with nested services
// so just generate a list of JSON objects and process them with a script
template { // https://github.com/hashicorp/consul-template/blob/master/docs/configuration.md#templates
  source      = "/etc/consul-template/config/load-balancer.json.ctmpl"
  destination = "/tmp/load-balancer.json"
  perms       = 0600
  command     = "just check-and-refresh"
  wait {
    // Min should be greater than consul service registation {"check": "interval": "2s"}
    min = "3s"
    max = "6s"
  }
}
