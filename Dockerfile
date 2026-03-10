# syntax=docker/dockerfile:1
FROM mcr.microsoft.com/playwright:v1.58.0-noble

RUN apt-get update && apt-get install -y --no-install-recommends \
  gnupg wget \
  && wget -qO- https://cloud.r-project.org/bin/linux/ubuntu/marutter_pubkey.asc \
    > /etc/apt/trusted.gpg.d/cran_ubuntu_key.asc \
  && echo "deb https://cloud.r-project.org/bin/linux/ubuntu noble-cran40/" \
    > /etc/apt/sources.list.d/cran-r.list \
  && apt-get update && apt-get install -y --no-install-recommends \
  git openssh-client ca-certificates gh \
  python3 python3-pip python3-venv make g++ \
  ripgrep jq \
  xvfb xauth \
  pulseaudio pulseaudio-utils \
  ffmpeg \
  r-base r-base-dev \
  && rm -rf /var/lib/apt/lists/*
RUN ln -s /usr/bin/python3 /usr/local/bin/python

# Codex CLI (npm package)
ARG NPM_CACHEBUST=1
RUN echo "npm cache bust: $NPM_CACHEBUST" >/dev/null && npm install -g npm@latest
RUN echo "codex cache bust: $NPM_CACHEBUST" >/dev/null && npm i -g @openai/codex

# Non-root user
RUN useradd -m -u 10001 -s /bin/bash codex

COPY scripts/codex-entrypoint.sh /usr/local/bin/codex-entrypoint.sh
RUN chmod +x /usr/local/bin/codex-entrypoint.sh

USER codex
WORKDIR /workspace
ENV PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1
ENV GIT_CONFIG_GLOBAL=/home/codex/.gitconfig
ENTRYPOINT ["/usr/local/bin/codex-entrypoint.sh"]
