FROM node:22-slim

# Overridden by the publish workflow with the contents of ./VERSION
ARG DSH_VERSION=latest
# Same pnpm the deepseek-harness repo pins; pnpm 12 fails plugin installs on ignored build scripts.
ARG PNPM_VERSION=11.7.0

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

COPY --chmod=755 entrypoint.sh /usr/local/bin/entrypoint.sh

USER node
WORKDIR /data/workspace
VOLUME /data
EXPOSE 3080

ENTRYPOINT ["tini", "--", "entrypoint.sh"]
