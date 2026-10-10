#!/usr/bin/env bash
# (Re)starts the app from whatever commit is checked out in /opt/shart-bag/app.
# Runs as root: by cloud-init on first boot, then by the "Server: create or update"
# workflow through Systems Manager after it checks out the new commit.
set -euo pipefail
export HOME="${HOME:-/root}" # Systems Manager runs commands without HOME set

APP=/opt/shart-bag/app
RUNTIME_ENV=/opt/shart-bag/runtime.env

# Written once at first boot by the instance's user data: TABLE_NAME, ORIGIN_SECRET_PARAM.
# shellcheck source=/dev/null
source /etc/shart-bag.env

# Region from the instance metadata service (IMDSv2).
token=$(curl -fsS -X PUT http://169.254.169.254/latest/api/token -H 'X-aws-ec2-metadata-token-ttl-seconds: 60')
region=$(curl -fsS -H "X-aws-ec2-metadata-token: $token" http://169.254.169.254/latest/meta-data/placement/region)

# The origin secret is read fresh on every deploy, so rotating it only needs a redeploy.
secret=$(aws ssm get-parameter --region "$region" --name "$ORIGIN_SECRET_PARAM" \
  --with-decryption --query Parameter.Value --output text)

umask 077
cat > "$RUNTIME_ENV" <<EOF
AWS_REGION=$region
TABLE_NAME=$TABLE_NAME
ORIGIN_SECRET=$secret
EOF

# Build the API image with plain "docker build", then start Compose without building.
# Amazon Linux ships an older Docker Engine than Compose's own build path is tested on;
# if BuildKit has trouble, fall back to the classic builder.
if ! docker build --quiet --tag shart-bag-api:server "$APP/api"; then
  echo "BuildKit build failed; retrying with the classic builder" >&2
  DOCKER_BUILDKIT=0 docker build --quiet --tag shart-bag-api:server "$APP/api"
fi

docker compose --env-file "$RUNTIME_ENV" -f "$APP/deploy/server/compose.yml" \
  up --detach --no-build --remove-orphans --wait --wait-timeout 300
docker image prune --force > /dev/null

echo "Deployed commit $(git -C "$APP" rev-parse --short HEAD)"
