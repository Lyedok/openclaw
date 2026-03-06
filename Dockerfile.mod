# stage с готовым docker-cli (+ плагины)
FROM docker:27-cli AS dockercli

# -------------------------
# Builder: ставим deps, собираем, оставляем только prod node_modules + dist
# -------------------------
FROM node:22-bookworm
#  AS builder

# Создаём каталог для плагинов
RUN mkdir -p /usr/local/libexec/docker/cli-plugins

# Копируем docker-cli и docker compose plugin
COPY --from=dockercli /usr/local/bin/docker /usr/local/bin/docker
COPY --from=dockercli \
  /usr/local/libexec/docker/cli-plugins/docker-compose \
  /usr/local/libexec/docker/cli-plugins/docker-compose

RUN corepack enable

# Make pnpm global binaries available for all users (incl. `node`)
ENV PNPM_HOME="/usr/local/share/pnpm"
ENV PATH="${PNPM_HOME}:${PATH}"
RUN mkdir -p "${PNPM_HOME}" && chown -R root:root "${PNPM_HOME}" && chmod -R 755 "${PNPM_HOME}"

# Group for download
RUN groupadd -g 3003 netbuild \
    && usermod -aG 3003 _apt \
    && usermod -aG 3003 node

WORKDIR /app
RUN chown node:node /app

# Copy and build
COPY --chown=node:node . .

USER node

ENV OPENCLAW_PREFER_PNPM=1
ENV CI=true
RUN pnpm install --frozen-lockfile && \
    pnpm build && \
    pnpm ui:build && \
    pnpm prune --prod && \
    pnpm store prune

USER root
RUN ln -sf /app/openclaw.mjs /usr/local/bin/openclaw \
 && chmod 755 /app/openclaw.mjs
ENV NODE_ENV=production

# Install apt packages
ARG OPENCLAW_DOCKER_APT_PACKAGES="curl ca-certificates jq ripgrep python3 sqlite3 cmake"
ARG AGENT_BROWSER_APT_PACKAGES="xvfb libxcb-shm0 libx11-xcb1 libx11-6 libxcb1 libxext6 libxrandr2 libxcomposite1 libxcursor1 libxdamage1 libxfixes3 libxi6 libgtk-3-0 libpangocairo-1.0-0 libpango-1.0-0 libatk1.0-0 libcairo-gobject2 libcairo2 libgdk-pixbuf-2.0-0 libxrender1 libasound2 libfreetype6 libfontconfig1 libdbus-1-3 libnss3 libnspr4 libatk-bridge2.0-0 libdrm2 libxkbcommon0 libatspi2.0-0 libcups2 libxshmfence1 libgbm1"
RUN echo 'APT::Sandbox::User "root";' > /etc/apt/apt.conf.d/99sandbox-root && \
    apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends $OPENCLAW_DOCKER_APT_PACKAGES $AGENT_BROWSER_APT_PACKAGES && \
    mkdir -p /home/node/.cache/ms-playwright && \
    PLAYWRIGHT_BROWSERS_PATH=/home/node/.cache/ms-playwright \
    node /app/node_modules/playwright-core/cli.js install --with-deps chromium && \
    chown -R node:node /home/node/.cache/ms-playwright && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*

# Change User
USER node

ENV BUN_INSTALL=/home/node/.bun
ENV PATH="/home/node/.bun/bin:${PATH}"
ENV NODE_LLAMA_CPP_CMAKE_OPTION_GGML_CUDA=OFF

RUN curl -fsSL https://bun.sh/install | bash && \
    bun install -g agent-browser && \
    bun install -g @tobilu/qmd && \
    qmd status

HEALTHCHECK --interval=3m --timeout=10s --start-period=15s --retries=3 \
  CMD node -e "fetch('http://127.0.0.1:18789/healthz').then((r)=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"
CMD ["node", "openclaw.mjs", "gateway", "--allow-unconfigured"]
# -------------------------
# Runtime: только то, что нужно для запуска
# -------------------------
# FROM node:22-bookworm AS runtime

# # docker-cli и docker compose plugin (как в исходнике)
# RUN mkdir -p /usr/local/libexec/docker/cli-plugins
# COPY --from=dockercli /usr/local/bin/docker /usr/local/bin/docker
# COPY --from=dockercli \
#   /usr/local/libexec/docker/cli-plugins/docker-compose \
#   /usr/local/libexec/docker/cli-plugins/docker-compose

# # (опционально) системные пакеты, если нужны во время работы
# ARG OPENCLAW_DOCKER_APT_PACKAGES="jq ripgrep"
# RUN if [ -n "$OPENCLAW_DOCKER_APT_PACKAGES" ]; then \
#       echo 'APT::Sandbox::User "root";' > /etc/apt/apt.conf.d/99sandbox-root && \
#       apt-get update && \
#       DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends $OPENCLAW_DOCKER_APT_PACKAGES && \
#       apt-get clean && \
#       rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*; \
#     fi

# ENV NODE_ENV=production
# WORKDIR /app

# # Перекладываем только артефакты
# COPY --from=builder /app/package.json ./package.json
# COPY --from=builder /app/node_modules ./node_modules
# COPY --from=builder /app/dist ./dist

# # Security hardening: Run as non-root user
# USER node

# CMD ["node", "dist/index.js", "gateway", "--allow-unconfigured"]
