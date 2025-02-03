# Find eligible builder and runner images on Docker Hub. We use Ubuntu/Debian
# instead of Alpine to avoid DNS resolution issues in production.
#
# https://hub.docker.com/r/hexpm/elixir/tags?page=1&name=ubuntu
# https://hub.docker.com/_/ubuntu?tab=tags
#
# This file is based on these images:
#
#   - https://hub.docker.com/r/hexpm/elixir/tags - for the build image
#   - https://hub.docker.com/_/debian?tab=tags&page=1&name=bullseye-20240408-slim - for the release image
#   - https://pkgs.org/ - resource for finding needed packages
#   - Ex: hexpm/elixir:1.16.2-erlang-26.2.4-debian-bullseye-20240408-slim
#

# https://hub.docker.com/layers/hexpm/elixir/1.18.2-erlang-26.2.5.7-debian-bookworm-20250113-slim/images/sha256-47fd62132c8abf45d93b198708da26a241ef02607fdc62b972011bd95a640dd4
#1.18.2-erlang-26.2.5.7-ubuntu-jammy-20240808

ARG ELIXIR_VERSION=1.18.2
ARG OTP_VERSION=26.2.5.7

ARG DEBIAN_VERSION=bookworm-20250113-slim

ARG BUILDER_IMAGE="hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}"
ARG RUNNER_IMAGE="debian:${DEBIAN_VERSION}"

FROM ${BUILDER_IMAGE} AS builder

# install build dependencies
RUN apt-get update -y && apt-get install -y build-essential git \
    && apt-get clean && rm -f /var/lib/apt/lists/*_*

RUN apt-get update -y && apt-get install apt-utils curl -y && apt-get remove nodejs-legacy libnode72 -y
RUN apt remove --purge libnode72 nodejs-legacy nodejs npm && apt autoremove

RUN curl -sL https://deb.nodesource.com/setup_20.x | bash -
RUN apt-get update -y && apt-get install -y -f nodejs \
    && apt-get clean && rm -f /var/lib/apt/lists/*_*

SHELL ["/bin/bash", "--login", "-c"]
RUN curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
# Download and install Node.js:
RUN nvm install 22

# # Download and install nvm:
RUN node --version
RUN npm --version

#prepare build dir
WORKDIR /app

# install hex + rebar
RUN mix local.hex --force && \
    mix local.rebar --force

# set build ENV
ENV MIX_ENV="prod"

COPY config/config.exs config/${MIX_ENV}.exs config/
# install mix dependencies
COPY mix.exs mix.lock ./
RUN mix deps.clean --all && mix deps.get --only $MIX_ENV

RUN mix deps.compile

COPY priv priv

COPY lib lib

COPY assets assets
RUN cd assets && npm install esbuild --save-dev && npm install ../deps/phoenix ../deps/phoenix_html ../deps/phoenix_live_view --save && cd

RUN mix assets.deploy

# # Compile the release
RUN mix compile

# # Changes to config/runtime.exs don't require recompiling the code
COPY config/runtime.exs config/

# COPY rel rel
RUN mix release

# # start a new build stage so that the final image will only contain
# # the compiled release and other runtime necessities
FROM ${RUNNER_IMAGE}

RUN apt-get update -y && \
    apt-get install -y libstdc++6 openssl libncurses5 locales ca-certificates \
    && apt-get clean && rm -f /var/lib/apt/lists/*_*

RUN apt-get update -y && \
    apt-get install -y python3 python3-pip
RUN apt-get update -y && apt-get install -y pipx
#RUN pip3 install --upgrade pip
#    && apt-get clean && rm -f /var/lib/apt/lists/*_*

#RUN pipx install --no-cache-dir neurokit2
RUN pipx install --include-deps neurokit2


# # Set the locale
RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen

ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

ENV ECTO_IPV6=true
ENV ERL_AFLAGS="-proto_dist inet6_tcp"

WORKDIR "/app"
RUN chown nobody /app

# set runner ENV
ENV MIX_ENV="prod"

# Only copy the final release from the build stage
COPY --from=builder --chown=nobody:root /app/_build/${MIX_ENV}/rel/sensocto ./

USER nobody

# If using an environment that doesn't automatically reap zombie processes, it is
# advised to add an init process such as tini via `apt-get install`
# above and adding an entrypoint. See https://github.com/krallin/tini for details
# ENTRYPOINT ["/tini", "--"]

CMD ["/app/bin/server"]
