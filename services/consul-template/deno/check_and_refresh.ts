/**
 * This exists because trying to create the correct nginx config with only the
 * templater is really hard and complex. So script instead.
 * 1. Get all services from /tmp/load-balancer.json (from consul-template)
 * 2. Generate nginx config
 * 3. Write nginx config to /etc/nginx/conf.d/load-balancer.certbot.conf
 *                          /etc/nginx/conf.d/load-balancer.https.conf
 * 4. Reload nginx
 */
import { exec, OutputMode } from "https://deno.land/x/exec@0.0.5/mod.ts";
import { existsSync } from "https://deno.land/std@0.132.0/fs/mod.ts";

type ServiceBlob = {
  name: string;
  address: string;
  port: number;
  tags: string[];
  meta: {
    domain: string;
    path: string;
  };
}

const blankServiceBlob :ServiceBlob = {
  name: "",
  address: "",
  port: 0,
  tags: [],
  meta: {
    domain: "",
    path: "",
  },
}

const reloadNginx = async () => {
  try {
    let response = await exec('just nginx-reload', {
      output: OutputMode.StdOut,
    });
    if (response.status.code !== 0) {
      console.log(response);
      throw new Error("Failed: just nginx-reload");
    }
  } catch(err) {
    console.log(`Failed to reload nginx: ${err}`);
  }
}

const getDomains = (services: ServiceBlob[]) => {
  const domains = services.map((service) => service.meta.domain);
  const uniqueDomains = [...new Set(domains)];
  return uniqueDomains;
}

const generateNginxCertbotConfig = (services: ServiceBlob[]) => {
  const domains = getDomains(services);

  return domains.map((domain) => {
    return `
server {
    listen 80;
    listen [::]:80;

    server_name ${domain};
    server_tokens off;

    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }

    location /healthcheck {
        add_header Content-Type text/plain;
        return 200 '${domain} is A-OK!';
    }

    location / {
      # redirect to https
      return 301 https://${domain}$request_uri;
    }
}
    `
  }).join("\n");
}


const generateNginxRoutingConfig = (services: ServiceBlob[]) => {
  const servicesGroupedByName : { [name: string]: ServiceBlob[] } = {};
  services.forEach(s => {
    if (!servicesGroupedByName[s.name]){
      servicesGroupedByName[s.name] = [];
    }
    servicesGroupedByName[s.name].push(s);
  });

  const servicesGroupedByDomain : { [name: string]: ServiceBlob[] } = {};
  services.forEach(s => {
    if (!servicesGroupedByDomain[s.meta.domain]){
      servicesGroupedByDomain[s.meta.domain] = [];
    }
    servicesGroupedByDomain[s.meta.domain].push(s);
  });

  // First do upstreams
  let config :string = '';
  Object.keys(servicesGroupedByName).forEach(serviceName => {
    const services = servicesGroupedByName[serviceName].map(service => {
      return `  server ${service.address}:${service.port} max_fails=3 fail_timeout=60 weight=1;`;
    }).join("\n");
    config += `
upstream ${serviceName} {
  zone upstream-${serviceName} 64k;
${services}
}
    `;
  });

  // Then the main server block(s)
  Object.keys(servicesGroupedByDomain).forEach(domain => {

    config +=
`
server {
  listen 443 ssl http2;
  listen [::]:443 ssl http2; # IPv6 support
  server_name ${domain};

  ## Start: Size Limits & Buffer Overflows ##
  client_body_buffer_size  1K;
  client_header_buffer_size 1k;
  large_client_header_buffers 2 4k;
  # But exception to us because we need to accept large payloads (currently)
  # This should be configurable, but needs work:
  # https://github.com/dionjwa/dynamic-dns-automatic/issues/2
  client_max_body_size 100M;
  client_body_timeout 10m;
  ## END: Size Limits & Buffer Overflows ##

  ## Start: Security best practices https://www.acunetix.com/blog/web-security-zone/hardening-nginx/
  server_tokens off; # disable the Server nginx header
  ssl_protocols TLSv1.2 TLSv1.3;
  ssl_prefer_server_ciphers on;
  ## END: Security best practices

  ## Start: Sensible defaults
  # without this, browser requests to e.g. _logout start a download
  default_type text/plain;
  # enable gzip
  gzip on;
  gzip_disable "msie6";
  gzip_comp_level 6;
  gzip_min_length 1100;
  gzip_buffers 16 8k;
  gzip_proxied any;
  gzip_types
      text/plain
      text/css
      text/js
      text/xml
      text/javascript
      application/javascript
      application/x-javascript
      application/json
      application/xml
      application/rss+xml
      image/svg+xml;
  ## END: Sensible defaults



  ssl_certificate /etc/nginx/ssl/live/${domain}/fullchain.pem;
  ssl_certificate_key /etc/nginx/ssl/live/${domain}/privkey.pem;

`;
  const pathsToServiceName :Record<string,string> = {};
  servicesGroupedByDomain[domain].forEach(service => {
    pathsToServiceName[service.meta.path] = service.name;
  });

  console.log('pathsToServiceName', pathsToServiceName);

  Object.keys(pathsToServiceName).forEach(path => {
    const pathWithoutFirstSlash = path.startsWith('/') ? path.substring(1) : path;
    config +=
`
  # Handle websockets
  location /${pathWithoutFirstSlash} {
      try_files /nonexistent @${pathWithoutFirstSlash}$http_upgrade;
  }
  location @${pathWithoutFirstSlash}websocket {
      proxy_pass http://${pathsToServiceName[path]};

      proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
      proxy_set_header Host $host;
      proxy_set_header X-Real-IP $remote_addr;
      # WebSocket support
      proxy_http_version 1.1;
      proxy_set_header Upgrade $http_upgrade;
      proxy_set_header Connection "upgrade";
      # Set 60-minute timeout between reads and writs
      # proxy_read_timeout 3600;
      # proxy_send_timeout 3600;
  }
  location @${pathWithoutFirstSlash} {
      # TODO: limit all except needed
      # https://www.acunetix.com/blog/web-security-zone/hardening-nginx/
      # limit_except GET HEAD POST { deny all; }
      proxy_set_header Host $host;
      proxy_pass http://${pathsToServiceName[path]};
  }

`
  });

  config += `
}
    `;
  });

  return config;
}

if (!existsSync("/tmp/load-balancer.json")) {
  console.error("/tmp/load-balancer.json does not exist");
  Deno.exit(0);
}
const loadBalancerJsonList :string =  await Deno.readTextFile("/tmp/load-balancer.json");
console.log(loadBalancerJsonList)


const Services :ServiceBlob[] = loadBalancerJsonList.split("\n")
.map(line => {
  console.log(`line before trimming: ${line}`);
  return line;
})
  .map(line => line.trim())
  .map(line => {
    console.log(`line after trimming: ${line}`);
    return line;
  })
  .filter(line => line.length > 0)
  .map(line => {
    let service :ServiceBlob|undefined;
    try {
      service = JSON.parse(line);
    } catch(err) {
      console.log(`Failed to parse: ${line}`);
      console.log(err);
    }
    return service || blankServiceBlob;
  })
  // only services I have tagged with "nginx-route" (better way?)
  .filter(service => service?.tags.includes("nginx-route") && service?.meta?.domain !== "");

console.log('Services', Services);

console.log('🐸 1: write certbot nginx config, so the certbot can validate certificate domains.');
// These files are shared via a volume with the nginx container
await Deno.writeTextFile("/etc/nginx/conf.d/load-balancer.certbot.conf", generateNginxCertbotConfig(Services));
console.log('🐸 2: restart nginx, so the certbot can validate certificate domains.');
console.log('🐸 2.1: But first if there are services that do not have existing certificates, nginx will exit with an error.');
console.log('🐸 2.2: So regenerate /etc/nginx/conf.d/load-balancer.https.conf with services removed that lack existing certificates');
await Deno.writeTextFile("/etc/nginx/conf.d/load-balancer.https.conf", generateNginxRoutingConfig(Services.filter(service => {
  const domain = service.meta.domain;
  const certFile = `/etc/nginx/ssl/live/${domain}/fullchain.pem`;
  const exists = existsSync(certFile);
  console.log(`🐸 2.2: excluding ${domain} from load-balancer.https.conf because the cert is not ready`);
  return exists;
})));
await reloadNginx();

// Certificate generation must be done first otherwise nginx will complain that it cannot
// find the certificates.
console.log('🐸 3: refresh certificates (maybe domains altered), certbot will validate certificate domains.');
for (const domain of getDomains(Services)) {
  let response = await exec(`just get-certificates ${domain}`, {
    output: OutputMode.StdOut,
  });
  if (response.status.code !== 0) {
    // don't completel quick, since maybe letsencrypt is down
    console.error(`just get-certificates ${domain} response=${JSON.stringify(response)}`);
  }
}

// These files are shared via a volume with the nginx container
console.log('🐸 4: write the entire nginx config, services with their paths, connected to the domains backed by certbot certificates.');
await Deno.writeTextFile("/etc/nginx/conf.d/load-balancer.https.conf", generateNginxRoutingConfig(Services));
console.log('🐸 5: restart nginx: we are good to go 👍');
await reloadNginx();
