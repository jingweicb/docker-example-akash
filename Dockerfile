FROM golang:1.21 as build
RUN \
    apt update \
 && apt install -y \
      bash \
      git \
      make \
      gcc \
      cmake \
      jq \
      curl \
      wget \
      build-essential \
      ca-certificates \
      npm \
      unzip

# Add the direnv installation command here
RUN wget https://github.com/direnv/direnv/releases/download/v2.32.1/direnv.linux-amd64 -O /usr/local/bin/direnv && \
    chmod +x /usr/local/bin/direnv 

ARG REPO_URL=https://github.com/akash-network/node

# %%RELEASE_COMMIT_HASH%%	ARM, PLEASE ENSURE THE RELEASE COMMIT HASH IS NEXT LINE
ARG COMMIT_HASH=f417f49214eafaf9181d258d429950d3591ae601
ARG RELEASE_TAG=v0.36.0

SHELL ["/usr/bin/bash", "-c"]

RUN git clone -n "${REPO_URL}" node \
    && cd node \
    && git checkout "${COMMIT_HASH}"

WORKDIR /go/node

RUN \
    direnv allow /go/node \
 && cd /go/node \
 && eval "$(direnv export bash)" \
 && make bins


# ============
#  Cosmovisor
# ============

FROM golang:1.21 AS cosmovisor-builder
RUN apt update && apt install -y bash clang tar wget musl-dev git make gcc bc ca-certificates

ARG GIT_REF=cosmovisor/v1.3.0
ARG REPO_URL=https://github.com/cosmos/cosmos-sdk
RUN git clone -n "${REPO_URL}" cosmos-sdk \
    && cd cosmos-sdk \
    && git fetch origin "${GIT_REF}" \
    && git reset --hard FETCH_HEAD

WORKDIR /go/cosmos-sdk/cosmovisor/

RUN go mod download
RUN make cosmovisor


###################
# Execution Stage #
###################
FROM ubuntu:22.04
RUN apt update && apt install jq lz4 -y cmake gcc make curl wget build-essential ca-certificates npm direnv

COPY --from=build /go/node/.cache/bin/* /usr/local/bin/
COPY --from=cosmovisor-builder /go/cosmos-sdk/cosmovisor/cosmovisor /usr/local/bin/

# TODO what is this
ARG USER_ID=1000
ARG GROUP_ID=1001
RUN useradd -m --uid ${USER_ID} akash && groupmod --gid ${GROUP_ID} akash && usermod -aG akash akash
RUN chown -R akash /home
USER akash

# will not enable auto-downloading of new binaries due to security concerns
ENV DAEMON_ALLOW_DOWNLOAD_BINARIES false
# path of an existing configuration file to use
ENV CONFIG_PATH "/app/assets"
# The keyring backend type https://docs.cosmos.network/master/run-node/keyring.html
ENV SEID_KEYRING_BACKEND file

WORKDIR /app
USER root
# Copy config files templates
COPY scripts/assets/ /app/assets
COPY scripts/entrypoint.sh /entrypoint.sh

EXPOSE 30656 26657 1317 9090

RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
