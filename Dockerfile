FROM node:22-slim

# Overridden by the publish workflow with the contents of ./VERSION
ARG DSH_VERSION=latest
# Same pnpm the deepseek-harness repo pins; pnpm 12 fails plugin installs on ignored build scripts.
ARG PNPM_VERSION=11.7.0
# Space-separated plugins preinstalled into the web profile.
ARG DSH_PLUGINS="dsh-remote@0.8.42"
ARG RCLONE_VERSION=1.75.2

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl fuse3 git openssh-client socat tini \
    && rm -rf /var/lib/apt/lists/*

# rclone reaches cloud drives (Google Drive, OneDrive, Proton Drive, ...); Debian's package is too old.
RUN set -eu; deb="rclone-v${RCLONE_VERSION}-linux-amd64.deb"; cd /tmp; \
    curl -fsSLO "https://downloads.rclone.org/v${RCLONE_VERSION}/${deb}"; \
    curl -fsSL "https://downloads.rclone.org/v${RCLONE_VERSION}/SHA256SUMS" | grep " ${deb}\$" | sha256sum -c -; \
    dpkg -i "$deb"; rm "$deb"

# pnpm is what dsh shells out to when installing plugins.
RUN npm install -g "@deepseek-ai/dsh@${DSH_VERSION}" "pnpm@${PNPM_VERSION}" \
    && npm cache clean --force

# Sessions, settings and credentials live in DSH_HOME; the agent works in /data/workspace.
# rclone keeps its config and cache in the volume too; mounts default to a bounded write cache.
ENV DSH_HOME=/data/.dsh \
    DSH_PORT=3080 \
    RCLONE_CONFIG=/data/.config/rclone/rclone.conf \
    RCLONE_CACHE_DIR=/data/.cache/rclone \
    RCLONE_VFS_CACHE_MODE=writes \
    RCLONE_VFS_CACHE_MAX_SIZE=1G
RUN mkdir -p /data/.dsh /data/workspace /data/.config/rclone /data/.cache/rclone && chown -R node:node /data

# Plugins are installed into a seed profile at build time; the entrypoint copies it
# into DSH_HOME when the volume has no web profile yet.
COPY profile/pnpm-workspace.yaml /opt/dsh-seed/profiles/web/pnpm-workspace.yaml
RUN set -eu; export DSH_HOME=/opt/dsh-seed; \
    for plugin in $DSH_PLUGINS; do \
        dsh plugin --profile web add "$plugin"; \
        test -d "$DSH_HOME/profiles/web/node_modules/${plugin%@*}"; \
    done; \
    rm -rf "$DSH_HOME/profiles/web/.plugin-manager/logs" "$DSH_HOME/logs"; \
    chown -R node:node "$DSH_HOME"

COPY --chmod=755 entrypoint.sh /usr/local/bin/entrypoint.sh

USER node
WORKDIR /data/workspace
VOLUME /data
EXPOSE 3080

ENTRYPOINT ["tini", "--", "entrypoint.sh"]
