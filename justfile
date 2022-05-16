# Set up a reverse proxy to route external requests to local applications
set shell       := ["bash", "-c"]
set dotenv-load := true
export ROOT                        := `git rev-parse --show-toplevel`
# Main config for the target host
export TARGET_HOST                 := env_var_or_default("TARGET_HOST", "localhost")
export TARGET_USER                 := env_var_or_default("TARGET_USER", "")
# GITHUB_TOKEN                       := env_var_or_default("GITHUB_TOKEN", "")
# Required for pulling/pushing images, not required for locally building and running.
# export DOCKER_REGISTRY             := env_var_or_default("DOCKER_REGISTRY", "ghcr.io/")
export DOCKER_REGISTRY             := env_var_or_default("DOCKER_REGISTRY", "registry.hub.docker.com/")
export DOCKER_IMAGE_PREFIX         := env_var_or_default("DOCKER_IMAGE_PREFIX", `(which deno >/dev/null && which git >/dev/null && deno run --unstable --allow-all https://deno.land/x/cloudseed@v0.0.19/cloudseed/docker_image_prefix.ts) || echo ''`)
export DOCKER_TAG                  := env_var_or_default("DOCKER_TAG", `(which deno >/dev/null && deno run --unstable --allow-all https://deno.land/x/cloudseed@v0.0.19/git/getGitSha.ts --short=8) || echo cache`)
export DOCKER_BUILDKIT             := env_var_or_default("DOCKER_BUILDKIT", "1")
DOCKER_USERNAME                    := env_var_or_default("DOCKER_USERNAME", "USERNAME")
DOCKER_PASSWORD                    := env_var_or_default("DOCKER_PASSWORD", "")
# minimal formatting, bold is very useful
bold                               := '\033[1m'
normal                             := '\033[0m'
green                              := "\\e[32m"
yellow                             := "\\e[33m"
blue                               := "\\e[34m"
magenta                            := "\\e[35m"
grey                               := "\\e[90m"

# Automatically mount the local file system in a docker container with all
# required tools. Sometimes there can be issues (but so far it's workable):
# mounting host directories is rife with permissions problems:
# https://github.com/moby/moby/issues/2259#issuecomment-48284631
_help:
    #!/usr/bin/env bash
    if [ -f /.dockerenv ]; then
        echo ""
        just --list --unsorted --list-heading $'🏡 Commands: (set up a remote instance to serve multiple services/domains via consul+nginx):\n'
        echo ""
        echo -e "   Current [deploy|delete|console] target (from .env and env vars):"
        echo -e "   {{green}}{{TARGET_USER}}{{normal}}@{{green}}{{TARGET_HOST}}{{normal}}"
        echo ""
    else
        # Get into the docker container, and in this directory
        just {{ROOT}}/_docker "$(echo $PWD/ | sd ${ROOT}/ '')";
    fi

# Develop: this story is not very well developed, because you need DNS
dev +args="consul-template consul refresh-certificates nginx": build
    @echo "Full development is limited, and many pieces rely on actual DNS updates. Just building and running locally"
    cd services && docker-compose up {{args}}

# docker-compose commands but with env vars from the justfile
dc +args="":
    cd services && docker-compose {{args}}

# Open the TARGET_HOST consul UI in a browser, must be on the same internal network as the server
console:
    open http://{{TARGET_HOST}}:8500/ui/local/services

# Deploy consul docker-compose stack to TARGET_HOST. Also requires CERTBOT_EMAIL TARGET_USER DOCKER_PASSWORD DOCKER_USERNAME
deploy: _docker_registry_authenticate build push _upload_to_remote_compose_config && _delete_local_remote_compose_config
    ssh -o ConnectTimeout=10 {{TARGET_USER}}@{{TARGET_HOST}} 'echo {{DOCKER_PASSWORD}} | docker login ghcr.io -u {{DOCKER_USERNAME}} --password-stdin'
    @# Workaround for https://github.com/qdm12/ddns-updater/issues/239
    ssh {{TARGET_USER}}@{{TARGET_HOST}} 'cd deployments/consul && mkdir -p dynamic-dns-updater/data && chown -R 1000 dynamic-dns-updater/data && chmod 700 dynamic-dns-updater/data && touch dynamic-dns-updater/data/config.json && chmod 400 dynamic-dns-updater/data/config.json'
    @# Ensure external volumes exist
    ssh {{TARGET_USER}}@{{TARGET_HOST}} 'if [ "$(docker volume inspect certbot-www  2>/dev/null)" = "[]" ]; then docker volume create certbot-www; fi'
    ssh {{TARGET_USER}}@{{TARGET_HOST}} 'if [ "$(docker volume inspect certbot-conf  2>/dev/null)" = "[]" ]; then docker volume create certbot-conf; fi'
    @# Start up the stack
    ssh {{TARGET_USER}}@{{TARGET_HOST}} 'cd deployments/consul && docker-compose pull && docker-compose up --force-recreate --remove-orphans -d'

_upload_to_remote_compose_config:
    cd services && docker-compose -f docker-compose.yml config > docker-compose.remote.yml
    ssh -o 'StrictHostKeyChecking accept-new' {{TARGET_USER}}@{{TARGET_HOST}} 'mkdir -p deployments/consul'
    scp services/docker-compose.remote.yml {{TARGET_USER}}@{{TARGET_HOST}}:deployments/consul/docker-compose.yml

@_delete_from_remote_compose_config:
    echo "Currently NOT deleting remove compose config, probably should tho, just need to validate"

@_delete_local_remote_compose_config:
    # rm -rf services/docker-compose.remote.yml

# Delete the consul docker-compose stack from TARGET_HOST
delete: _upload_to_remote_compose_config && _delete_local_remote_compose_config
    @# Bring down the stack
    ssh {{TARGET_USER}}@{{TARGET_HOST}} 'cd deployments/consul && docker-compose down -v || true'
    ssh {{TARGET_USER}}@{{TARGET_HOST}} 'docker volume rm certbot-www certbot-conf || true'

build:
    #!/usr/bin/env bash
    set -euo pipefail
    cd services/
    # just consul/setup
    # buildx uses different a different command structure ugh
    if [ "${DOCKER_BUILDKIT}" = "1" ]; then
        echo -e " 🏗️ buildkit enabled!"
        # Guide: https://medium.com/@artur.klauser/building-multi-architecture-docker-images-with-buildx-27d80f7e2408
        # buildkit is required for multi-architecture builds
        # buildkit ignores custom docker-compose.yml set in DOCKER_COMPOSE_ARGS, the compose yaml parsing is not the same
        # as non-buildkit builds and errors abound
        # buildx pushes to the buildkit registry to requires authentication
        # I saw this 👇 here 👉 https://github.com/marthoc/docker-deconz/blob/master/.travis.yml and https://medium.com/@artur.klauser/building-multi-architecture-docker-images-with-buildx-27d80f7e2408
        # echo -e " 🏗️ docker run --rm --privileged --platform linux/arm64/v8 multiarch/qemu-user-static --reset -p yes"
        # docker run --rm --privileged --platform linux/arm64/v8 multiarch/qemu-user-static --reset -p yes
        if [ "$(docker buildx ls | grep multi-builder)" = "" ]; then
            echo -e " 🏗️ buildkit builder 'multi-builder' does not exist, creating"
            docker buildx create --name multi-builder
        else
            echo -e " 🏗️ buildkit builder already exists"
        fi
        docker buildx use multi-builder
        COMPOSE_DOCKER_CLI_BUILD=1 DOCKER_TAG=$DOCKER_TAG DOCKER_REGISTRY=$DOCKER_REGISTRY DOCKER_IMAGE_PREFIX=$DOCKER_IMAGE_PREFIX docker buildx bake --push --set '*.platform=linux/arm64,linux/amd64' -f docker-compose.yml -f docker-compose.build.yml
        docker buildx use default
    else
        echo -e "🚪 {{bold}}DOCKER_TAG=$DOCKER_TAG DOCKER_REGISTRY=$DOCKER_REGISTRY DOCKER_IMAGE_PREFIX=$DOCKER_IMAGE_PREFIX docker-compose -f docker-compose.yml -f docker-compose.build.yml build {{normal}} 🚪 ";
        DOCKER_TAG=$DOCKER_TAG DOCKER_REGISTRY=$DOCKER_REGISTRY DOCKER_IMAGE_PREFIX=$DOCKER_IMAGE_PREFIX docker-compose -f docker-compose.yml -f docker-compose.build.yml build;
    fi

push: build _docker_registry_authenticate
    #!/usr/bin/env bash
    set -euo pipefail
    cd services
    # buildx uses different a different command structure ugh
    if [ "${DOCKER_BUILDKIT}" = "1" ]; then
        echo -e " 🏗️ buildkit enabled! No pushing (handled as part of buildkit build)"
    else
        echo -e "🚪 {{bold}}DOCKER_TAG=$DOCKER_TAG DOCKER_REGISTRY=$DOCKER_REGISTRY DOCKER_IMAGE_PREFIX=$DOCKER_IMAGE_PREFIX docker-compose -f docker-compose.yml -f docker-compose.build.yml push {{normal}} 🚪 ";
        DOCKER_TAG=$DOCKER_TAG DOCKER_REGISTRY=$DOCKER_REGISTRY DOCKER_IMAGE_PREFIX=$DOCKER_IMAGE_PREFIX docker-compose -f docker-compose.yml -f docker-compose.build.yml push;
    fi

_docker_registry_authenticate:
    #!/usr/bin/env bash
    set -euo pipefail
    if [[ -z "{{DOCKER_PASSWORD}}" ]]; then
        echo "🚪 🔥🔥🔥 Required but missing: DOCKER_PASSWORD. Set in .env or via the provider docker context 🚪 ";
        exit 1;
    fi
    if [[ -z "{{DOCKER_USERNAME}}" ]]; then
        echo "🚪 🔥🔥🔥 Required but missing: DOCKER_USERNAME. Set in .env or via the provider docker context 🚪 ";
        exit 1;
    fi
    if [ -f ~/.docker/config.json ] && [ "$(cat ~/.docker/config.json | jq -r --arg DOCKER_REGISTRY $(echo $DOCKER_REGISTRY | sd '/' '') '.auths[$DOCKER_REGISTRY]')" != "null" ]; then
        echo "🤖 👍 docker registry is already authenticated for DOCKER_REGISTRY=$DOCKER_REGISTRY";
        exit 0;
    fi

    echo {{DOCKER_PASSWORD}} | docker login -u {{DOCKER_USERNAME}} --password-stdin $(echo $DOCKER_REGISTRY | sd '/' '')
    echo "🤖 ✅ docker registry authenticated: $(echo $DOCKER_REGISTRY | sd '/' '')";

# Build and run the ci/cloud image, used for building, publishing, and deployments
_docker dir="": _docker_build
    echo -e "🚪🚪 Entering docker context: {{bold}}{{DOCKER_IMAGE_PREFIX}}cloud:{{DOCKER_TAG}} from <cloud/>Dockerfile 🚪🚪{{normal}}"
    mkdir -p {{ROOT}}/.tmp
    touch {{ROOT}}/.tmp/.bash_history

    export WORKSPACE={{ROOT}} && \
        docker run \
            --rm \
            -ti \
            -e DOCKER_IMAGE_PREFIX=${DOCKER_IMAGE_PREFIX} \
            -e PS1="< \w/> " \
            -e PROMPT="<%/% > " \
            -e DOCKER_IMAGE_PREFIX={{DOCKER_IMAGE_PREFIX}} \
            -e HISTFILE=$WORKSPACE/.tmp/.bash_history \
            -e WORKSPACE=$WORKSPACE \
            -v {{ROOT}}:$WORKSPACE \
            -v $HOME/.ssh:/root/.ssh \
            -v deno:/root/.deno \
            -v /var/run/docker.sock:/var/run/docker.sock \
            -w $WORKSPACE \
            {{DOCKER_IMAGE_PREFIX}}cloud:{{DOCKER_TAG}} bash || true

# If the ./app docker image in not build, then build it
@_docker_build:
    echo -e "🚪🚪  ➡ {{bold}}Building ./cloud docker image ...{{normal}} 🚪🚪 "
    echo -e "🚪 </> {{bold}} docker build -t {{DOCKER_IMAGE_PREFIX}}cloud:{{DOCKER_TAG}} . {{normal}}🚪 "
    docker build -t {{DOCKER_IMAGE_PREFIX}}cloud:{{DOCKER_TAG}} .

_docker_ensure_inside:
    #!/usr/bin/env bash
    set -euo pipefail
    if [ ! -f /.dockerenv ]; then
        echo -e "🌵🔥🌵🔥🌵🔥🌵 First run the command: just 🌵🔥🌵🔥🌵🔥🌵"
        exit 1
    fi
