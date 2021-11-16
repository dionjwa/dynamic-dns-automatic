# Automatic Dynamic DNS on a single machine

Register your service with consul and https routing and certificates are automated.

[Installation](#installation) to a remote machine via a single command.

## Tasks

### Add a new service

1. Add/edit the DynamicDNS updater (if required):
  - `dynamic-dns-updater/config.json`: https://github.com/qdm12/ddns-updater#configuration
2. Start a service named as the domain with `.` replaced by `_`:  `my.domain.com` => `my_domain_com`:
  - `docker run --rm -d --name my_domain_com -e PORT=3010 -p 3010:3010 ealen/echo-server`
  - `my_domain_com` will be rendered as `my.domain.com` in nginx
3. Register the service (called "my_domain_com") with consul:
  - `curl --request PUT --data '{"id":"my_domain_com","name":"my_domain_com","port":3010,"check":{"name":"HTTP API on port 3010","interval": "2s","http":"http://localhost:3010"}}' localhost:8500/v1/agent/service/register`
    - https://www.consul.io/docs/discovery/services
    - Make sure that `"interval": "2s"` is less than `consul-template/config/consul-template-config.hcl:` `min = "3s"`
      - consul doesn't seem to get the timing right on rendering, the service must be registered as healthy *before* the templating process starts. This is not how consul is advertised to work (re-renders on any updates) and is possibly due to timing of the template render.
  - `consul` triggers an update to `consul-template` that updates `nginx`
4. Check URL, should work (URL is user controlled)
  - `curl https://my.domain.com` (or whatever you register)

### Remove a service

```
  curl --request PUT localhost:8500/v1/agent/service/deregister/my_domain_com
```

https://www.consul.io/docs/discovery/services

### Installation

1. Clone this repo
   - Optional (TODO: is this required?):
     - add keys certs: https://learn.hashicorp.com/tutorials/consul/deployment-guide
     - TODO: this could be justfiled
2. Required:
   - Host machine:
     - `just` installed: https://github.com/casey/just
     - `docker`
     - ssh access to remote machine
     - `GITHUB_TOKEN` with `ghcr.io` write access
     - env vars defined in `.env` or in env (values are examples):
       - `GITHUB_TOKEN=xxxxxxxxxxxx`
         - Host machine needs to push docker images
         - Remote machine needs to pull docker images
       - `TARGET_HOST=192.168.86.10`
       - `TARGET_USER=admin`
       - `CERTBOT_EMAIL=admin@mydomain.io`
   - Remote machine:
     - `docker`
     - External DNS configuration pointing to this machine (optional only needed for dynamic DNS):
       1. Add/edit the DynamicDNS updater (if required):
       2. `dynamic-dns-updater/config.json`: https://github.com/qdm12/ddns-updater#configuration
3. Intall:
   - `just`
   - TODO


### Architecture

Docker containers: `consul`, `nginx`, `certbot`, `consul-template`, plus `qmcgaw/ddns-updater`

And a little bit of scripting.

### Useful commands for debugging (on the remote machine)

#### See nginx https config

docker exec -ti dynamic-dns-nginx cat /etc/nginx/conf.d/load-balancer.https.conf

#### Run the templater manually

docker exec -ti dynamic-dns-consul-template consul-template -once -log-level debug -config=/etc/consul-template/config/consul-template-config.hcl

## Reference blogs

https://mindsers.blog/post/https-using-nginx-certbot-docker/

## Similar repos

 - https://github.com/snw35/le-docker
   - does not use consul, does not automatically renew proxying and certificates on new services
