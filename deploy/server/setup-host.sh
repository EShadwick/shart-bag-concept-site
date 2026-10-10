#!/usr/bin/env bash
# Prepares an Amazon Linux 2023 host to run the app: swap, Docker, Docker Compose and Buildx,
# plus a nightly power-off backstop. Runs as root on first boot and again on every deploy.
# Safe to run any number of times.
set -euo pipefail

# Pinned, checksum-verified plugin versions. Amazon Linux 2023 packages Docker itself but
# not these plugins. Compose needs Buildx 0.17 or newer to build images.
COMPOSE_VERSION=5.5.1
BUILDX_VERSION=0.37.0
PLUGINS=/usr/local/lib/docker/cli-plugins

case "$(uname -m)" in
  aarch64) compose_arch=aarch64 buildx_arch=arm64 ;;
  x86_64) compose_arch=x86_64 buildx_arch=amd64 ;;
  *) echo "Unsupported CPU architecture: $(uname -m)" >&2; exit 1 ;;
esac

# 1 GB of swap so image builds fit on a 1 GB instance.
if ! swapon --show=NAME --noheadings | grep -qx /swapfile; then
  if [ ! -f /swapfile ]; then
    fallocate -l 1G /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
  fi
  swapon /swapfile
fi
grep -q '^/swapfile ' /etc/fstab || echo '/swapfile swap swap defaults 0 0' >> /etc/fstab

dnf install -y --quiet docker
systemctl enable --now docker

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$PLUGINS"

# download URL FILE: fetch into the temp folder, retrying through brief network hiccups.
download() { curl -fsSL --retry 5 --retry-all-errors -o "$tmp/$2" "$1"; }

if ! docker compose version 2>/dev/null | grep -q "v$COMPOSE_VERSION"; then
  file="docker-compose-linux-$compose_arch"
  base="https://github.com/docker/compose/releases/download/v$COMPOSE_VERSION"
  download "$base/$file" "$file"
  download "$base/$file.sha256" "$file.sha256"
  (cd "$tmp" && sha256sum --check --strict "$file.sha256")
  install -m 0755 "$tmp/$file" "$PLUGINS/docker-compose"
fi

if ! docker buildx version 2>/dev/null | grep -q "v$BUILDX_VERSION"; then
  file="buildx-v$BUILDX_VERSION.linux-$buildx_arch"
  base="https://github.com/docker/buildx/releases/download/v$BUILDX_VERSION"
  download "$base/$file" "$file"
  download "$base/checksums.txt" checksums.txt
  (cd "$tmp" && grep -E " [*]?$file\$" checksums.txt | sha256sum --check --strict)
  install -m 0755 "$tmp/$file" "$PLUGINS/docker-buildx"
fi

# Backstop for the nightly "Server: stop" workflow, in case a scheduled GitHub run is delayed,
# dropped or waiting for approval. The instance's shutdown behavior is "stop", so this stops
# (never terminates) it. Persistent=false: starting the server later in the day does not
# trigger a missed run.
cat > /etc/systemd/system/nightly-stop.service <<'EOF'
[Unit]
Description=Stop this server for the night (backstop for the "Server: stop" workflow)

[Service]
Type=oneshot
ExecStart=/usr/bin/systemctl poweroff
EOF
cat > /etc/systemd/system/nightly-stop.timer <<'EOF'
[Unit]
Description=Nightly stop at 09:30 UTC

[Timer]
OnCalendar=*-*-* 09:30:00 UTC
Persistent=false

[Install]
WantedBy=timers.target
EOF
systemctl daemon-reload
systemctl enable --now nightly-stop.timer

docker compose version
docker buildx version
