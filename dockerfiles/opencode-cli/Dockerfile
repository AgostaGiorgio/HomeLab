# syntax=docker/dockerfile:1
#
# OpenCode CLI image used as a blackbox runner for n8n-launched Kubernetes Jobs.
#
# The image only provides the CLI (plus git/ripgrep and the default config).
# The actual command (`opencode run ...`) lives in the Job manifest that n8n
# sends, so model/agent/prompt stay visible and editable from n8n.
#
# The container runs as uid 1000 (the `node` user) so files it creates on the
# shared hostPath volume stay owned by the same uid as n8n.
#
# Models come from an OpenCode Go subscription (provider id `opencode-go`,
# authenticated with OPENCODE_API_KEY).
#
# Build & push:
#   docker build -t registry/opencode-cli:latest dockerfiles/opencode-cli
#   docker push registry/opencode-cli:latest

#VERSION 1.0.0

FROM node:22-bookworm-slim

# Pin the CLI for reproducible builds, e.g. --build-arg OPENCODE_VERSION=2.0.24
ARG OPENCODE_VERSION=latest

# git for repository work, ripgrep for the agent's search tool.
RUN apt-get update \
 && apt-get install -y --no-install-recommends git ripgrep ca-certificates \
 && rm -rf /var/lib/apt/lists/* \
 && npm install --global "@opencode/cli@${OPENCODE_VERSION}" \
 && npm cache clean --force

USER node
ENV HOME=/home/node
WORKDIR /data/shared

COPY --chown=node:node opencode.jsonc /home/node/.config/opencode/opencode.jsonc

# `opencode` is the default; Jobs override command/args to run `opencode run ...`.
ENTRYPOINT ["opencode"]
CMD ["--help"]
