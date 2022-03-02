FROM alpine:3.14
RUN apk --no-cache --update add \
    bash \
    curl \
    docker \
    docker-compose \
    ripgrep \
    wget

# sd is better than sed
RUN apk add sd --repository=http://dl-cdn.alpinelinux.org/alpine/edge/testing/

# consul-template for updating e.g. nginx configs
RUN VERSION=0.27.2 ; \
    wget https://releases.hashicorp.com/consul-template/${VERSION}/consul-template_${VERSION}_linux_amd64.zip && \
    unzip consul-template_${VERSION}_linux_amd64.zip && \
    rm -rf consul-template_${VERSION}_linux_amd64.zip && \
    mv consul-template usr/local/bin/

# justfile for running commands, you will mostly interact with just https://github.com/casey/just
RUN VERSION=0.9.1 ; \
    SHA256SUM=054d2e02804b635da051d33cb120d76963fc1dc027b21a2f618bf579632b9c94 ; \
    curl -L -O https://github.com/casey/just/releases/download/v$VERSION/just-v$VERSION-x86_64-unknown-linux-musl.tar.gz && \
    (echo "$SHA256SUM  just-v$VERSION-x86_64-unknown-linux-musl.tar.gz" | sha256sum  -c -) && \
    mkdir -p /tmp/just && mv just-v$VERSION-x86_64-unknown-linux-musl.tar.gz /tmp/just && cd /tmp/just && \
    tar -xzf just-v$VERSION-x86_64-unknown-linux-musl.tar.gz && \
    mkdir -p /usr/local/bin && mv /tmp/just/just /usr/local/bin/ && rm -rf /tmp/just
# just tweak: unify the just binary location on host and container platforms because otherwise the shebang doesn't work properly due to no string token parsing (it gets one giant string)
ENV PATH $PATH:/usr/local/bin
# alias "j" to just, it's just right there index finger
RUN echo -e '#!/bin/bash\njust "$@"' > /usr/bin/j && \
    chmod +x /usr/bin/j


# Required to communicate with consul
COPY config /etc/consul-template/config
# COPY certs /etc/consul.d/client/certs

# command: "consul-template -config=/etc/consul-template/config/consul-template-config.hcl"
# 2021/11/15 20:32:26 [ERR] (cli) missing file/folder: /etc/consul-template/consul-template-config.hcl: stat /etc/consul-template/consul-template-config.hcl: no such file or directory

WORKDIR /etc/consul-template
# This has all our commands
COPY justfile ./
COPY refresh-certificates  /etc/periodic/15min/refresh-certificates

CMD consul-template -log-level debug -config=/etc/consul-template/config/consul-template-config.hcl
