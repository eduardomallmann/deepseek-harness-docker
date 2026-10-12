FROM node:22-slim

# Overridden by the publish workflow with the contents of ./VERSION
ARG DSH_VERSION=latest
# Same pnpm the deepseek-harness repo pins; pnpm 12 fails plugin installs on ignored build scripts.
ARG PNPM_VERSION=11.7.0
# Space-separated plugins preinstalled into the web profile.
ARG DSH_PLUGINS="dsh-remote@0.8.42"

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates git openssh-client socat tini \
    && rm -rf /var/lib/apt/lists/*

# pnpm is what dsh shells out to when installing plugins.
RUN npm install -g "@deepseek-ai/dsh@${DSH_VERSION}" "pnpm@${PNPM_VERSION}" \
    && npm cache clean --force

# Sessions, settings and credentials live in DSH_HOME; the agent works in /data/workspace.
ENV DSH_HOME=/data/.dsh \
    DSH_PORT=3080
RUN mkdir -p /data/.dsh /data/workspace && chown -R node:node /data

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
