# Set up a reverse proxy to route external requests to local applications
set shell := ["bash", "-c"]
export ROOT                        := `git rev-parse --show-toplevel`
export TARGET_HOST                 := env_var_or_default("TARGET_HOST", "localhost")
export TARGET_USER                 := env_var_or_default("TARGET_USER", "")
GITHUB_TOKEN                       := env_var_or_default("GITHUB_TOKEN", "")
# Required for pulling/pushing images, not required for locally building and running.
export DOCKER_REGISTRY             := env_var_or_default("DOCKER_REGISTRY", "ghcr.io/")
export DOCKER_IMAGE_PREFIX         := env_var_or_default("DOCKER_IMAGE_PREFIX", `(which deno >/dev/null && which git >/dev/null && deno run --unstable --allow-all https://deno.land/x/cloudseed@v0.0.18/cloudseed/docker_image_prefix.ts) || echo ''`)
export DOCKER_TAG                  := env_var_or_default("DOCKER_TAG", `(which deno >/dev/null && deno run --unstable --allow-all https://deno.land/x/cloudseed@v0.0.18/git/getGitSha.ts --short=8) || echo cache`)
bold     := '\033[1m'
normal   := '\033[0m'

# Automatically mount the local file system in a docker container with all
# required tools. Sometimes there can be issues (but so far it's workable):
# mounting host directories is rife with permissions problems:
# https://github.com/moby/moby/issues/2259#issuecomment-48284631
_help:
    #!/usr/bin/env bash
    if [ -f /.dockerenv ]; then
        echo ""
        just --list --unsorted --list-heading $'🏡 Set up a local machine to serve multiple services/domains:\n'
        echo ""
    else
        # Get into the docker container, and in this directory
        just {{ROOT}}/_docker "$(echo $PWD/ | sd ${ROOT}/ '')";
    fi

# Open the consul UI in a browser, must be on the same internal network as the server
console:
    open http://{{TARGET_HOST}}:8500/ui/local/services

# Deploy consul docker-compose stack to TARGET_HOST. Also requires CERTBOT_EMAIL TARGET_USER GITHUB_TOKEN
deploy: _docker_registry_authenticate
    docker-compose -f docker-compose.yml -f docker-compose.build.yml build
    docker-compose -f docker-compose.yml -f docker-compose.build.yml push
    docker-compose config > docker-compose.remote.yml
    ssh {{TARGET_USER}}@{{TARGET_HOST}} 'mkdir -p deployments/consul'
    scp docker-compose.remote.yml {{TARGET_USER}}@{{TARGET_HOST}}:deployments/consul/docker-compose.yml
    rm docker-compose.remote.yml
    ssh -o ConnectTimeout=10 {{TARGET_USER}}@{{TARGET_HOST}} 'echo {{GITHUB_TOKEN}} | docker login ghcr.io -u USERNAME --password-stdin'
    @# Workaround for https://github.com/qdm12/ddns-updater/issues/239
    ssh {{TARGET_USER}}@{{TARGET_HOST}} 'cd deployments/consul && mkdir -p dynamic-dns-updater/data && sudo chown -R 1000 dynamic-dns-updater/data && chmod 700 dynamic-dns-updater/data && touch dynamic-dns-updater/data/config.json && chmod 400 dynamic-dns-updater/data/config.json'
    @# Ensure external volumes exist
    ssh {{TARGET_USER}}@{{TARGET_HOST}} 'if [ "$(docker volume inspect certbot-www  2>/dev/null)" = "[]" ]; then docker volume create certbot-www; fi'
    ssh {{TARGET_USER}}@{{TARGET_HOST}} 'if [ "$(docker volume inspect certbot-conf  2>/dev/null)" = "[]" ]; then docker volume create certbot-conf; fi'
    @# Start up the stack
    ssh {{TARGET_USER}}@{{TARGET_HOST}} 'cd deployments/consul && docker-compose pull && docker-compose up --remove-orphans -d'

_docker_registry_authenticate:
    #!/usr/bin/env bash
    set -euo pipefail
    if [[ -z "$GITHUB_TOKEN" ]]; then
        echo "🚪 🔥🔥🔥 Required but missing: GITHUB_TOKEN. Set in .env or via the provider docker context 🚪 ";
        exit 1;
    fi
    echo -e "🚪 <ci/> {{bold}}echo GITHUB_TOKEN | docker login --username USERNAME --password-stdin ghcr.io{{normal}} 🚪"
    echo $GITHUB_TOKEN | docker login -u USERNAME --password-stdin ghcr.io

# Build and run the ci/cloud image, used for building, publishing, and deployments
_docker dir="": _docker_build
    echo -e "🚪🚪 Entering docker context: {{bold}}{{DOCKER_IMAGE_PREFIX}}cloud:{{DOCKER_TAG}} from <cloud/>Dockerfile 🚪🚪{{normal}}"
    mkdir -p {{ROOT}}/.tmp
    touch {{ROOT}}/.tmp/.bash_history
    export WORKSPACE=/repo && \
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
            -v /var/run/docker.sock:/var/run/docker.sock \
            -w $WORKSPACE/{{dir}} \
            {{DOCKER_IMAGE_PREFIX}}cloud:{{DOCKER_TAG}} bash || true

# If the ./app docker image in not build, then build it
@_docker_build:
    echo -e "🚪🚪  ➡ {{bold}}Building ./cloud docker image ...{{normal}} 🚪🚪 "
    echo -e "🚪 </> {{bold}} docker build -f {{ROOT}}/Dockerfile -t {{DOCKER_IMAGE_PREFIX}}cloud:{{DOCKER_TAG}} . {{normal}}🚪 "
    docker build -f {{ROOT}}/Dockerfile -t {{DOCKER_IMAGE_PREFIX}}cloud:{{DOCKER_TAG}} .

_docker_ensure_inside:
    #!/usr/bin/env bash
    set -euo pipefail
    if [ ! -f /.dockerenv ]; then
        echo -e "🌵🔥🌵🔥🌵🔥🌵 First run the command: just 🌵🔥🌵🔥🌵🔥🌵"
        exit 1
    fi
