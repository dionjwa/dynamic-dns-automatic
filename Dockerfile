# Install all CLI/CI tools for deploying the application
FROM denoland/deno:alpine-1.16.1

RUN apk --no-cache --update add \
    bash \
    curl \
    docker \
    docker-compose \
    git \
    jq \
    ncurses \
    openssh-client

# sd is better than sed
RUN apk add sd --repository=http://dl-cdn.alpinelinux.org/alpine/edge/testing/

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

# watchexec for live reloading in development https://github.com/watchexec/watchexec
RUN VERSION=1.14.1 ; \
    SHA256SUM=34126cfe93c9c723fbba413ca68b3fd6189bd16bfda48ebaa9cab56e5529d825 ; \
    curl -L -O https://github.com/watchexec/watchexec/releases/download/$VERSION/watchexec-$VERSION-i686-unknown-linux-musl.tar.xz && \
    (echo "$SHA256SUM  watchexec-${VERSION}-i686-unknown-linux-musl.tar.xz" | sha256sum -c) && \
    tar xvf watchexec-$VERSION-i686-unknown-linux-musl.tar.xz watchexec-$VERSION-i686-unknown-linux-musl/watchexec -C /usr/bin/ --strip-components=1 && \
    rm -rf watchexec-*

# deno for scripting
ENV DENO_VERSION=1.5.3
RUN apk add --virtual .download --no-cache curl ; \
    SHA256SUM=2452296818a057db9bf307bd72c5da15883108415c1f7bd4f86153e3bce5cd44 ; \
    curl -fsSL https://github.com/denoland/deno/releases/download/v${DENO_VERSION}/deno-x86_64-unknown-linux-gnu.zip --output deno.zip \
    && (echo "$SHA256SUM  deno.zip" | sha256sum -c) \
    && unzip deno.zip \
    && rm deno.zip \
    && chmod 777 deno \
    && mv deno /bin/deno \
    && apk del .download

ENV DENO_DIR=/root/.deno

# Our workdir
WORKDIR /repo

###################################################################################################
# final config
###################################################################################################

# Show the just help on shell entry
RUN echo 'if [ -f justfile ]; then just; fi' >> /root/.bashrc
