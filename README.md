# Automatic Dynamic DNS on a single machine

[![](https://mermaid.ink/svg/eyJjb2RlIjoiZ3JhcGggTFJcbiAgbmdpbnhcbiAgY2VydGJvdFxuICBjb25zdWxcbiAgY29uc3VsLXRlbXBsYXRlXG4gIGRvbWFpbnJlZ2lzdGVyW1tETlMgbXkuZG9tYWluLmlvXV1cbiAgc2VydmljZShbc2VydmljZSBmb3IgbXkuZG9tYWluLmlvXSlcbiAgc3ViZ3JhcGggXCJSZW1vdGUgaW5zdGFuY2UgXCJcbiAgICBzZXJ2aWNlIC0tPiB8cmVnaXN0ZXIgc2VydmljZSBlbmRwb250fCBjb25zdWxcbiAgICBjb25zdWwgLS0-IHx1cGRhdGVzfCBjb25zdWwtdGVtcGxhdGVcbiAgICBjb25zdWwtdGVtcGxhdGUgLS0-IHxnZXQgaHR0cHMgY2VydHN8IGNlcnRib3RcbiAgICBjb25zdWwtdGVtcGxhdGUgLS0-IHx1cGRhdGVzIG15LmRvbWFpbi5pbyByb3V0ZXwgbmdpbnhcbiAgICBkeW5hbWljLWRucy11cGRhdGVyXG4gICAgbmdpbnggLS0-IHxwcm94eSBob3N0Om15LmRvbWFpbi5pb3wgc2VydmljZVxuICBlbmRcbiAgZHluYW1pYy1kbnMtdXBkYXRlciAtLT4gfCBVcGRhdGVzIG15LmRvbWFpbi5pbyAtPiBwdWJsaWMgSVAgfGRvbWFpbnJlZ2lzdGVyXG4gIGJyb3dzZXIgLS0-IHxteS5kb21haW4uaW8vaW5kZXguaHRtbHwgZG9tYWlucmVnaXN0ZXJcbiAgZG9tYWlucmVnaXN0ZXIgLS0-IHxteS5kb21haW4uaW8vaW5kZXguaHRtbHwgbmdpbnhcbiAgXG5cdFx0IiwibWVybWFpZCI6eyJ0aGVtZSI6ImRlZmF1bHQifSwidXBkYXRlRWRpdG9yIjpmYWxzZSwiYXV0b1N5bmMiOnRydWUsInVwZGF0ZURpYWdyYW0iOmZhbHNlfQ)](https://mermaid-js.github.io/mermaid-live-editor/edit#eyJjb2RlIjoiZ3JhcGggTFJcbiAgbmdpbnhcbiAgY2VydGJvdFxuICBjb25zdWxcbiAgY29uc3VsLXRlbXBsYXRlXG4gIGRvbWFpbnJlZ2lzdGVyW1tETlMgbXkuZG9tYWluLmlvXV1cbiAgc2VydmljZShbc2VydmljZSBmb3IgbXkuZG9tYWluLmlvXSlcbiAgc3ViZ3JhcGggXCJSZW1vdGUgaW5zdGFuY2UgXCJcbiAgICBzZXJ2aWNlIC0tPiB8cmVnaXN0ZXIgc2VydmljZSBlbmRwb250fCBjb25zdWxcbiAgICBjb25zdWwgLS0-IHx1cGRhdGVzfCBjb25zdWwtdGVtcGxhdGVcbiAgICBjb25zdWwtdGVtcGxhdGUgLS0-IHxnZXQgaHR0cHMgY2VydHN8IGNlcnRib3RcbiAgICBjb25zdWwtdGVtcGxhdGUgLS0-IHx1cGRhdGVzIG15LmRvbWFpbi5pbyByb3V0ZXwgbmdpbnhcbiAgICBkeW5hbWljLWRucy11cGRhdGVyXG4gICAgbmdpbnggLS0-IHxwcm94eSBob3N0Om15LmRvbWFpbi5pb3wgc2VydmljZVxuICBlbmRcbiAgZHluYW1pYy1kbnMtdXBkYXRlciAtLT4gfCBVcGRhdGVzIG15LmRvbWFpbi5pbyAtPiBwdWJsaWMgSVAgfGRvbWFpbnJlZ2lzdGVyXG4gIGJyb3dzZXIgLS0-IHxteS5kb21haW4uaW8vaW5kZXguaHRtbHwgZG9tYWlucmVnaXN0ZXJcbiAgZG9tYWlucmVnaXN0ZXIgLS0-IHxteS5kb21haW4uaW8vaW5kZXguaHRtbHwgbmdpbnhcbiAgXG5cdFx0IiwibWVybWFpZCI6IntcbiAgXCJ0aGVtZVwiOiBcImRlZmF1bHRcIlxufSIsInVwZGF0ZUVkaXRvciI6ZmFsc2UsImF1dG9TeW5jIjp0cnVlLCJ1cGRhdGVEaWFncmFtIjpmYWxzZX0)

Target: you have a single machine reverse proxying your services.

[Register your service](#add-a-new-service) with consul => https routing and letsencrypt certificates are automated.

[Installation](#installation) to a remote machine via a single command.

## Tasks

### Add a new service

**Short version:** (you have everything else set up already)

1. Remote: register the service (called "my_domain_com") with consul:
  - `curl --request PUT --data '{"id":"my_domain_com","name":"my_domain_com","port":3010,"check":{"name":"HTTP API on port 3010","interval": "2s","http":"http://localhost:3010"}}' localhost:8500/v1/agent/service/register`
2. That's it. Routing and certificates are handled automatically.
   - Multiple services on the same route can register, nginx will round-robin requests

**Long version:**

1. Host: add/edit the DynamicDNS updater (if required):
  - `dynamic-dns-updater/config.json`: https://github.com/qdm12/ddns-updater#configuration
  - `just deploy` to update the host
2. Remote: start a service named as the domain with `.` replaced by `_`:  `my.domain.com` => `my_domain_com`:
  - `docker run --rm -d --name my_domain_com -e PORT=3010 -p 3010:3010 ealen/echo-server`
  - `my_domain_com` will be rendered as `my.domain.com` in nginx
  - This example is startin the service on the host, but the service can be anywhere as long as it is reachable
3. Remote: register the service (called "my_domain_com") with consul:
  - `curl --request PUT --data '{"id":"my_domain_com","name":"my_domain_com","port":3010,"check":{"name":"HTTP API on port 3010","interval": "2s","http":"http://localhost:3010"}}' localhost:8500/v1/agent/service/register`
    - https://www.consul.io/docs/discovery/services
    - Make sure that `"interval": "2s"` is less than `consul-template/config/consul-template-config.hcl:` `min = "3s"`
      - consul doesn't seem to get the timing right on rendering, the service must be registered as healthy *before* the templating process starts. This is not how consul is advertised to work (re-renders on any updates) and is possibly due to timing of the template render.
  - `consul` triggers an update to `consul-template` that updates `nginx`
4. Check URL, should work (URL is user controlled)
  - `curl https://my.domain.com` (or whatever you register)

### Remove a service

Remote:

```
  curl --request PUT localhost:8500/v1/agent/service/deregister/my_domain_com
```

https://www.consul.io/docs/discovery/services

### Installation

1. Host: clone this repo
   - Optional (TODO: is this required?):
     - add keys certs: https://learn.hashicorp.com/tutorials/consul/deployment-guide
     - TODO: this could be justfiled
2. Required:
   - Host machine:
     - `just` installed: https://github.com/casey/just
     - `docker`
     - ssh access to remote machine
     - env vars defined in `.env` or in env (values are examples):
       - `GITHUB_TOKEN=xxxxxxxxxxxx`
         - with `ghcr.io` write access
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
3. Host: install containers to remote
   - `just` (enters docker container with host mounted in)
   - `just deploy`: starts linked docker containers on host
4. [Add a new service](#add-a-new-service)


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
