# stage с готовым docker-cli (+ плагины)
FROM docker:27-cli AS dockercli

# -------------------------
# Builder: ставим deps, собираем, оставляем только prod node_modules + dist
# -------------------------
FROM node:22-bookworm@sha256:cd7bcd2e7a1e6f72052feb023c7f6b722205d3fcab7bbcbd2d1bfdab10b1e935
#  AS builder

# Install Bun (required for build scripts)
RUN echo 'APT::Sandbox::User "root";' > /etc/apt/apt.conf.d/99sandbox-root && \
    apt-get update && \
    apt-get install -y --no-install-recommends curl ca-certificates jq ripgrep && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*
RUN curl -fsSL https://bun.sh/install | bash
ENV PATH="/root/.bun/bin:${PATH}"

# Создаём каталог для плагинов (на всякий случай)
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

WORKDIR /app

# Копируем исходники
COPY --chown=node:node . .
USER node
ENV OPENCLAW_PREFER_PNPM=1
ENV NODE_ENV=production
ENV CI=true

RUN pnpm install --frozen-lockfile && \
    pnpm build && \
    pnpm ui:build && \
    pnpm prune --prod && \
    pnpm store prune

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
