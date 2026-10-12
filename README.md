# deepseek-harness-docker

Unofficial Docker image for the [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) web UI (`@deepseek-ai/dsh`). Not affiliated with DeepSeek.

The image installs the official npm package unmodified and runs `dsh --profile web`. Nothing in dsh is patched.

> **dsh is a coding agent that runs shell commands.** Anyone who reaches the UI with a valid session has a shell in the container. Never publish the port to an untrusted network: put it behind a VPN or an authenticating reverse proxy with TLS.

## Run

```bash
docker run -d --name dsh \
  -p 127.0.0.1:3080:3080 \
  -v dsh-data:/data \
  ghcr.io/eduardomallmann/deepseek-harness:latest

docker logs dsh | grep "dsh web:"   # tokenized launch URL (a credential)
```

Open `http://127.0.0.1:3080/?token=...` using the token from the log line (the log prints the internal port; use the published one).

## Configuration

| Variable | Default | Purpose |
|---|---|---|
| `DSH_PORT` | `3080` | Port exposed by the container. |
| `DSH_TRUSTED_HOSTS` | unset | Comma-separated authorities (`host` or `host:port`) browsers use to reach dsh, e.g. the reverse proxy hostname. Other non-loopback `Host` values get `403` on `/api`. |
| `DSH_HOST` | unset | Bind dsh natively to this concrete address and skip the relay. Needs dsh `>= 0.2.1`; wildcards are rejected. |
| `DSH_PUBLIC_URL` | unset | Passed as `--public-url`. Needs dsh `>= 0.2.1`. |
| `DSH_INTERNAL_PORT` | `3079` | Loopback port dsh uses in relay mode. |
| `DEEPSEEK_API_KEY` | unset | Optional; the key can also be saved in Settings → Models. |

Data lives under `/data` (run as user `node`, uid 1000):

- `/data/.dsh` (`DSH_HOME`): sessions, settings, credentials.
- `/data/workspace`: the agent's working directory.

### Bundled plugins

The image ships with [`dsh-remote`](https://github.com/flymysql/dsh-remote) (SSH remote workspaces) preinstalled. Plugins are baked into a seed profile and copied to `/data/.dsh/profiles/web` the first time the container starts on a volume that has no web profile. An existing profile is never touched, so on an older volume add the plugin from the UI or with `dsh plugin --profile web add dsh-remote`.

To change the bundled set, edit the `DSH_PLUGINS` build argument in the `Dockerfile` (space-separated `name@version`). If a plugin's dependencies have build scripts, list them under `allowBuilds` in `profile/pnpm-workspace.yaml`, otherwise pnpm fails the install.

More plugins can be added at runtime from the UI; they are stored in the volume.

### Cloud drives (rclone)

[rclone](https://rclone.org/) is included so documents on Google Drive, OneDrive, Proton Drive and other backends can be used as folders. Its config lives in the volume at `/data/.config/rclone/rclone.conf` (`RCLONE_CONFIG`).

Create a remote (OAuth backends need a browser, so authorize on a desktop and paste the token when `rclone config` asks for it):

```bash
# on a machine with a browser: prints a token after you log in
docker run --rm -it --network host ghcr.io/eduardomallmann/deepseek-harness:latest \
  rclone authorize "drive" "<client_id>" "<client_secret>"

# in the running container: create the remote, answering "n" to "use web browser"
docker exec -it dsh rclone config
```

Mount remotes at start with `RCLONE_MOUNTS`, a comma-separated list of `remote:path=/mount/point`:

```bash
docker run -d --name dsh \
  --device /dev/fuse --cap-add SYS_ADMIN --security-opt apparmor:unconfined \
  -e RCLONE_MOUNTS="gdrive:=/data/drive/gdrive" \
  -p 127.0.0.1:3080:3080 -v dsh-data:/data \
  ghcr.io/eduardomallmann/deepseek-harness:latest
```

Mounting needs `/dev/fuse` and `SYS_ADMIN`, which widen what a shell in the container can do; without them the mount fails with a log line and dsh still starts. Without mounting, `rclone copy`/`rclone sync` work unprivileged. Mounts use `--vfs-cache-mode writes` with a 1 GB cache by default; override with rclone's own `RCLONE_*` variables.

### Why a relay

Releases up to `0.2.0` only bind `127.0.0.1` and refuse `0.0.0.0`. By default the entrypoint keeps dsh on loopback and runs `socat` to forward the container's own address to it. From `0.2.1` on, set `DSH_HOST` to the container address to bind natively instead.

## Updating the dsh version

1. Edit `VERSION` (one line, an `@deepseek-ai/dsh` version) and push to `main`.
2. The `Publish image` workflow builds and pushes `:<version>` and `:latest`.
3. On the host: `docker compose pull dsh && docker compose up -d`.

To publish a one-off version without committing, run the workflow manually with the `version` input.

Images go to `ghcr.io/<owner>/deepseek-harness`. To also publish to Docker Hub, set the repository variable `DOCKERHUB_USERNAME` and the secret `DOCKERHUB_TOKEN`.

## Build locally

```bash
docker build --build-arg DSH_VERSION="$(cat VERSION)" -t deepseek-harness:local .
```

The image is about 800 MB; most of it is the dsh package and its dependencies.
