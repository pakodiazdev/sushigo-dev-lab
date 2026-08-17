#!/bin/sh
set -eu

# ---------------------------------------------------------------------------
# entrypoint.sh — Regenerates pgAdmin's server definition and pgpass file
# from POSTGRES_USER/POSTGRES_PASSWORD on every container start, then hands
# off to the image's own entrypoint.
#
# The base dpage/pgadmin4 image only copies PGPASS_FILE into place on first
# boot (when its internal sqlite db doesn't exist yet) — on a persisted
# pgadmin-data volume, a later credential change would never reach the
# stored .pgpass. Regenerating both files unconditionally here, every start,
# keeps them correct regardless of what's already in the volume.
#
# PGADMIN_REPLACE_SERVERS_ON_STARTUP=True (set in docker-compose.yml) makes
# the image's own entrypoint re-import servers.json into pgAdmin's internal
# server list on every start too, not just the first — see /entrypoint.sh.
# ---------------------------------------------------------------------------

: "${POSTGRES_USER:?POSTGRES_USER is required}"
: "${POSTGRES_PASSWORD:?POSTGRES_PASSWORD is required}"
: "${POSTGRES_HOST:=db}"
: "${POSTGRES_PORT:=5432}"

SERVERS_JSON_FILE="${PGADMIN_SERVER_JSON_FILE:-/pgadmin4/servers.json}"
PGPASS_FILE="/var/lib/pgadmin/.pgpass"

cat > "${SERVERS_JSON_FILE}" <<EOF
{
  "Servers": {
    "1": {
      "Name": "sushigo-dev-lab",
      "Group": "Servers",
      "Host": "${POSTGRES_HOST}",
      "Port": ${POSTGRES_PORT},
      "MaintenanceDB": "postgres",
      "Username": "${POSTGRES_USER}",
      "SSLMode": "prefer",
      "Favorite": true
    }
  }
}
EOF

echo "${POSTGRES_HOST}:${POSTGRES_PORT}:*:${POSTGRES_USER}:${POSTGRES_PASSWORD}" > "${PGPASS_FILE}"
chmod 600 "${PGPASS_FILE}"

exec /entrypoint.sh
