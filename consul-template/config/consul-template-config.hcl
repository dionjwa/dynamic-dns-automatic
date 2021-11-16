consul {
  address = "localhost:8500"

  retry {
    enabled  = true
    attempts = 12
    backoff  = "250ms"
  }
}
// Render the https config first but DO NOT yet copy it into the nginx
// directory, the certs might not yet exist, then nginx will fail and
// break our current timeline. we will copy it manually AFTER we have
// checked the certificates exist
template {
  source      = "/etc/consul-template/config/load-balancer.https.conf.ctmpl"
  // This spot is temporary until we validate we have the certs
  destination = "/etc/consul-template/load-balancer.https.conf"
}
// This template can immediately be copied into the nginx directory
template { // https://github.com/hashicorp/consul-template/blob/master/docs/configuration.md#templates
  source      = "/etc/consul-template/config/load-balancer.certbot.conf.ctmpl"
  destination = "/etc/nginx/conf.d/load-balancer.certbot.conf"
  perms       = 0600
  command     = "just check-and-refresh"
  wait {
    // Min should be greater than consul service registation {"check": "interval": "2s"}
    min = "3s"
    max = "6s"
  }
}
