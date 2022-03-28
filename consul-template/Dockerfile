# This Dockerfile is for doing CI type operations on the /app content and /cloud/*
#  - build/test/publish
#  - running the dev stack is done via the host, NOT with this image, due to docker/host/browser complications
#  - deploy via terraform/terragrunt
#
# Tools:
#  - docker + docker-compose
#  - just
#  - watchexec
#  - deno
#  - jq

# deno requires this special glibc compatible version of alpine alpine
FROM frolvlad/alpine-glibc:alpine-3.15_glibc-2.34

RUN apk --no-cache --update add \
    bash \
    curl \
    docker \
    ripgrep \
    wget

WORKDIR /root/

###############################################################################
# Install deno
# https://github.com/austinrivas/deno-alpine/blob/master/Dockerfile
ENV DENO_VERSION=1.20.3
RUN apk add --virtual .download --no-cache curl \
  && curl -fsSL https://github.com/denoland/deno/releases/download/v${DENO_VERSION}/deno-x86_64-unknown-linux-gnu.zip \
          --output deno.zip \
  && unzip deno.zip \
  && rm deno.zip \
  && chmod 777 deno \
  && mv deno /bin/deno \
  && apk del .download
###############################################################################

###############################################################################
# Needs edge repo
RUN apk add --no-cache -X http://dl-cdn.alpinelinux.org/alpine/edge/testing \
    sd
###############################################################################

###############################################################################
# consul-template for updating e.g. nginx configs
RUN VERSION=0.27.2 ; \
    wget https://releases.hashicorp.com/consul-template/${VERSION}/consul-template_${VERSION}_linux_amd64.zip && \
    unzip consul-template_${VERSION}_linux_amd64.zip && \
    rm -rf consul-template_${VERSION}_linux_amd64.zip && \
    mv consul-template /usr/local/bin/
###############################################################################

###############################################################################
# justfile for running commands, you will mostly interact with just https://github.com/casey/just
RUN VERSION=1.0.0 ; \
    SHA256SUM=342f8582d929b9212ffcbe9f7749e12908053cf215eb8d4a965c47ea2f24b0a4 ; \
    curl -L -O https://github.com/casey/just/releases/download/$VERSION/just-$VERSION-x86_64-unknown-linux-musl.tar.gz && \
    (echo "$SHA256SUM  just-$VERSION-x86_64-unknown-linux-musl.tar.gz" | sha256sum -c -) && \
    mkdir -p /usr/local/bin && \
    tar -xzf just-$VERSION-x86_64-unknown-linux-musl.tar.gz -C /usr/local/bin just && \
    rm -rf just-$VERSION-x86_64-unknown-linux-musl.tar.gz
# Unify the just binary location on host and container platforms because otherwise the shebang doesn't work properly due to no string token parsing (it gets one giant string)
ENV PATH $PATH:/usr/local/bin
# alias "j" to just, it's just right there index finger
RUN echo -e '#!/bin/bash\njust "$@"' > /usr/bin/j && \
    chmod +x /usr/bin/j
###############################################################################

###############################################################################
# docker-compose
RUN VERSION=2.3.4 ; \
    apk add --no-cache \
        docker \
        py-pip \
        python3-dev \
        libffi-dev \
        openssl-dev \
        gcc \
        libc-dev \
        rust \
        cargo \
        make && \
    curl -L "https://github.com/docker/compose/releases/download/v$VERSION/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose && \
    chmod +x /usr/local/bin/docker-compose && \
    apk del \
        py-pip \
        python3-dev \
        libffi-dev \
        openssl-dev \
        gcc \
        libc-dev \
        rust \
        cargo \
        make
###############################################################################

###############################################################################
# Local files
# Required to communicate with consul
COPY config /etc/consul-template/config
COPY deno /etc/consul-template/deno

WORKDIR /etc/consul-template
# This has all our commands
COPY justfile ./
COPY refresh-certificates  /etc/periodic/weekly/refresh-certificates

CMD consul-template -log-level debug -config=/etc/consul-template/config/consul-template-config.hcl
