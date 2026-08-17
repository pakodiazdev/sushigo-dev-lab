#!/bin/bash
set -euo pipefail

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
#
# Runs as /bin/bash rather than /bin/sh (matching docker-compose.yml's
# entrypoint override) so this follows the same convention as every other
# .sh file in the repo — verified the pgAdmin image ships bash.
# ---------------------------------------------------------------------------

: "${POSTGRES_USER:?POSTGRES_USER is required}"
: "${POSTGRES_PASSWORD:?POSTGRES_PASSWORD is required}"
: "${POSTGRES_HOST:=db}"
: "${POSTGRES_PORT:=5432}"

SERVERS_JSON_FILE="${PGADMIN_SERVER_JSON_FILE:-/pgadmin4/servers.json}"
PGPASS_FILE="/var/lib/pgadmin/.pgpass"

# json_escape <value>
# Escapes backslash and double-quote so value is safe inside a JSON string
# literal — POSTGRES_USER is attacker/operator controlled, not guaranteed
# to be JSON-safe as-is.
json_escape() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  printf '%s' "${value}"
}

# pgpass_escape <value>
# Escapes backslash and colon per the .pgpass format (colon is the field
# separator; a literal backslash or colon in any field — most importantly
# the password — must be backslash-escaped or the entry silently
# misaligns and password-less auth fails).
pgpass_escape() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//:/\\:}"
  printf '%s' "${value}"
}

cat > "${SERVERS_JSON_FILE}" <<EOF
{
  "Servers": {
    "1": {
      "Name": "sushigo-dev-lab",
      "Group": "Servers",
      "Host": "$(json_escape "${POSTGRES_HOST}")",
      "Port": ${POSTGRES_PORT},
      "MaintenanceDB": "postgres",
      "Username": "$(json_escape "${POSTGRES_USER}")",
      "SSLMode": "prefer",
      "Favorite": true
    }
  }
}
EOF

printf '%s:%s:*:%s:%s\n' \
  "$(pgpass_escape "${POSTGRES_HOST}")" \
  "$(pgpass_escape "${POSTGRES_PORT}")" \
  "$(pgpass_escape "${POSTGRES_USER}")" \
  "$(pgpass_escape "${POSTGRES_PASSWORD}")" > "${PGPASS_FILE}"
chmod 600 "${PGPASS_FILE}"

exec /entrypoint.sh
