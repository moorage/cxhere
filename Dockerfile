# syntax=docker/dockerfile:1
FROM ubuntu:25.10

ARG DEBIAN_FRONTEND=noninteractive
ARG NODE_VERSION=25.8.1
ARG NPM_CACHEBUST=1

ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8

RUN apt-get update && apt-get install -y --no-install-recommends \
  ca-certificates curl gnupg wget xz-utils \
  && wget -qO /etc/apt/trusted.gpg.d/ngrok.asc \
    https://ngrok-agent.s3.amazonaws.com/ngrok.asc \
  && echo "deb https://ngrok-agent.s3.amazonaws.com bookworm main" \
    > /etc/apt/sources.list.d/ngrok.list \
  && apt-get update && apt-get install -y --no-install-recommends \
  ffmpeg \
  fonts-freefont-ttf fonts-ipafont-gothic fonts-liberation fonts-noto-color-emoji \
  fonts-tlwg-loma-otf fonts-unifont fonts-wqy-zenhei \
  git openssh-client ca-certificates gh \
  gstreamer1.0-libav gstreamer1.0-plugins-bad gstreamer1.0-plugins-base gstreamer1.0-plugins-good \
  jq \
  libasound2t64 libatk-bridge2.0-0t64 libatk1.0-0t64 libatspi2.0-0t64 \
  libavcodec61 libavif16 libcairo-gobject2 libcairo2 libcups2t64 libdbus-1-3 \
  libdrm2 libegl1 libenchant-2-2 libepoxy0 libevent-2.1-7t64 libflite1 \
  libfontconfig1 libfreetype6 libgbm1 libgdk-pixbuf-2.0-0 libgles2 \
  libglib2.0-0t64 libgstreamer-gl1.0-0 libgstreamer-plugins-bad1.0-0 \
  libgstreamer-plugins-base1.0-0 libgstreamer1.0-0 libgtk-3-0t64 libgtk-4-1 \
  libharfbuzz-icu0 libharfbuzz0b libhyphen0 libicu76 libjpeg-turbo8 liblcms2-2 \
  libmanette-0.2-0 libnspr4 libnss3 libopus0 libpango-1.0-0 libpangocairo-1.0-0 \
  libpng16-16t64 libsecret-1-0 libsoup-3.0-0 libvpx9 libwayland-client0 \
  libwayland-egl1 libwayland-server0 libwebp7 libwebpdemux2 libwoff1 \
  libx11-6 libx11-xcb1 libxcb-shm0 libxcb1 libx264-164 libxcomposite1 \
  libxcursor1 libxdamage1 libxext6 libxfixes3 libxi6 libxkbcommon0 libxml2-16 \
  libxrandr2 libxrender1 libxslt1.1 \
  make g++ \
  ngrok \
  procps \
  pulseaudio pulseaudio-utils \
  python3 python3-pip python3-venv \
  r-base r-base-dev \
  ripgrep \
  xauth xfonts-cyrillic xfonts-scalable xvfb \
  && rm -rf /var/lib/apt/lists/*

RUN set -eux; \
  arch="$(dpkg --print-architecture)"; \
  case "$arch" in \
    amd64) node_arch='x64' ;; \
    arm64) node_arch='arm64' ;; \
    *) echo "unsupported architecture: $arch" >&2; exit 1 ;; \
  esac; \
  curl -fsSLO "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-${node_arch}.tar.xz"; \
  curl -fsSLO "https://nodejs.org/dist/v${NODE_VERSION}/SHASUMS256.txt"; \
  grep " node-v${NODE_VERSION}-linux-${node_arch}.tar.xz\$" SHASUMS256.txt | sha256sum -c -; \
  tar -xJf "node-v${NODE_VERSION}-linux-${node_arch}.tar.xz" -C /usr/local --strip-components=1 --no-same-owner; \
  rm -f "node-v${NODE_VERSION}-linux-${node_arch}.tar.xz" SHASUMS256.txt; \
  node --version; \
  npm --version

RUN ln -s /usr/bin/python3 /usr/local/bin/python

# Codex CLI (npm package)
RUN echo "npm cache bust: $NPM_CACHEBUST" >/dev/null && npm install -g npm@latest
RUN echo "codex cache bust: $NPM_CACHEBUST" >/dev/null && npm i -g @openai/codex

# Non-root user
RUN useradd -m -u 10001 -s /bin/bash codex

RUN mv /usr/local/bin/ngrok /usr/local/bin/ngrok-real
RUN mv /usr/bin/gh /usr/local/bin/gh-real
COPY scripts/codex-entrypoint.sh /usr/local/bin/codex-entrypoint.sh
COPY scripts/ngrok-wrapper.sh /usr/local/bin/ngrok
COPY scripts/gh-wrapper.sh /usr/local/bin/gh
RUN chmod +x /usr/local/bin/codex-entrypoint.sh
RUN chmod +x /usr/local/bin/ngrok
RUN chmod +x /usr/local/bin/gh

USER codex
WORKDIR /workspace
ENV PLAYWRIGHT_BROWSERS_PATH=/workspace/.pw-browsers
ENV GIT_CONFIG_GLOBAL=/home/codex/.gitconfig
ENTRYPOINT ["/usr/local/bin/codex-entrypoint.sh"]
