FROM hashicorp/consul:1.10.4
COPY ./certs/local-server-consul-0.pem /etc/consul.d/server/certs/
COPY ./certs/local-server-consul-0-key.pem /etc/consul.d/server/certs/
COPY ./certs/consul-agent-ca.pem /etc/consul.d/server/certs/
COPY ./consul.hcl /etc/consul.d/
# RUN chmod 640 /etc/consul.d/consul.hcl
COPY ./server.hcl /etc/consul.d/
# RUN chmod 640 /etc/consul.d/server.hcl
