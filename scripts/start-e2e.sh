#!/bin/bash
set -euo pipefail

# ---------------------------------------------------------------------------
# start-e2e.sh — Launch the E2E stack for one workspace
#
# Starts a lightweight PHP Docker container (volume-mounted to the workspace
# code), creates the E2E database, runs migrations, launches a Vite E2E dev
# server on a separate port, and prints the Cypress command to run.
#
# Usage:
#   ./scripts/start-e2e.sh sushigo-a
#   ./scripts/start-e2e.sh a
# ---------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

TARGET="${1:-}"

if [ -z "$TARGET" ]; then
  echo "Usage: $0 <workspace>"
  echo "Example: $0 sushigo-a"
  exit 1
fi

# Normalize: accept "a" or "sushigo-a"
if [[ "$TARGET" == sushigo-* ]]; then
  TARGET="${TARGET#sushigo-}"
fi

if ! [[ "$TARGET" =~ ^[a-h]$ ]]; then
  echo "❌ Invalid workspace: ${TARGET} (expected a–h)"
  exit 1
fi

LETTER="${TARGET}"
LETTER_UPPER="$(echo "${LETTER}" | tr '[:lower:]' '[:upper:]')"
WS_NAME="sushigo-${LETTER}"
WS_DIR="${ROOT_DIR}/workspaces/${WS_NAME}"
CONTAINER="e2e-api-${LETTER}"
DB_NAME="sushigo_ws_${LETTER}_e2e"

if [ ! -f "${WS_DIR}/.env" ]; then
  echo "❌ Workspace not found or not initialized: ${WS_NAME}"
  echo "   Run: ./scripts/setup.sh --workspaces=1 first"
  exit 1
fi

# Load tools.env for port config
if [ -f "${ROOT_DIR}/tools.env" ]; then
  # shellcheck source=/dev/null
  source "${ROOT_DIR}/tools.env"
fi

_e2e_api_var="E2E_API_PORT_${LETTER_UPPER}"
_e2e_vite_var="E2E_VITE_PORT_${LETTER_UPPER}"
E2E_API_PORT="${!_e2e_api_var:-$((8900 + $(echo "${LETTER}" | tr 'a-h' '12345678')))}"
E2E_VITE_PORT="${!_e2e_vite_var:-$((5180 + $(echo "${LETTER}" | tr 'a-h' '12345678')))}"

PG_USER="${POSTGRES_USER:-admin}"
PG_PASS="${POSTGRES_PASSWORD:-admin}"
PG_HOST="${POSTGRES_HOST:-127.0.0.1}"
PG_PORT="${POSTGRES_HOST_PORT:-5432}"
export PGPASSWORD="${PG_PASS}"

PID_FILE="${ROOT_DIR}/.e2e-vite-${LETTER}.pid"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  E2E — ${WS_NAME}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  API container → http://127.0.0.1:${E2E_API_PORT}"
echo "  Vite E2E      → http://localhost:${E2E_VITE_PORT}"
echo "  Database      → ${DB_NAME}"
echo ""

# ── Start e2e-api container ─────────────────────────────────────────────────
SERVICE="e2e-api-${LETTER}"
echo "🐳 Starting ${SERVICE}..."
docker compose \
  -f "${ROOT_DIR}/docker-compose.yml" \
  -f "${ROOT_DIR}/docker-compose.e2e.yml" \
  up "${SERVICE}" -d --build

# Resolve actual container name (Docker Compose prefixes with project name)
CONTAINER="$(docker compose \
  -f "${ROOT_DIR}/docker-compose.yml" \
  -f "${ROOT_DIR}/docker-compose.e2e.yml" \
  ps --format '{{.Name}}' "${SERVICE}" | head -1)"

if [ -z "${CONTAINER}" ]; then
  echo "❌ Could not determine container name for ${SERVICE}"
  exit 1
fi

echo "⏳ Waiting for container to be ready..."
RETRIES=30
until docker exec "${CONTAINER}" php -r "echo 'ok';" &>/dev/null 2>&1; do
  RETRIES=$((RETRIES - 1))
  if [ "$RETRIES" -eq 0 ]; then
    echo "❌ Container ${CONTAINER} did not become ready in time"
    exit 1
  fi
  sleep 1
done
echo "✅ Container ready"

# ── Copy APP_KEY from workspace .env into the container ─────────────────────
APP_KEY=$(grep "^APP_KEY=" "${WS_DIR}/code/api/.env" 2>/dev/null | cut -d'=' -f2- || true)
if [ -n "${APP_KEY}" ]; then
  docker exec "${CONTAINER}" bash -c "grep -q '^APP_KEY=' /app/.env 2>/dev/null \
    && sed -i 's|^APP_KEY=.*|APP_KEY=${APP_KEY}|' /app/.env \
    || echo 'APP_KEY=${APP_KEY}' >> /app/.env" 2>/dev/null || true
fi

# ── Create E2E database ──────────────────────────────────────────────────────
echo "🗄️  Creating database ${DB_NAME}..."
CREATE_OUT="$(psql -h "${PG_HOST}" -p "${PG_PORT}" -U "${PG_USER}" \
  -d postgres -c "CREATE DATABASE ${DB_NAME};" 2>&1)" || true
if echo "${CREATE_OUT}" | grep -q "already exists"; then
  echo "  ℹ️  Database already exists — skipping"
elif echo "${CREATE_OUT}" | grep -qi "error\|fatal\|permission"; then
  echo "❌ Failed to create database: ${CREATE_OUT}"
  exit 1
else
  echo "  ✅ Database created"
fi

# ── Migrate and seed ─────────────────────────────────────────────────────────
echo "🛠  Running migrations..."
docker exec "${CONTAINER}" php artisan migrate --force --quiet

echo "🌱 Seeding..."
docker exec "${CONTAINER}" php artisan db:seed --force --quiet

# ── Launch Vite E2E dev server ───────────────────────────────────────────────
echo "⚡ Starting Vite E2E server on port ${E2E_VITE_PORT}..."
VITE_API_URL="http://localhost:${E2E_API_PORT}/api/v1" \
  npm --prefix "${WS_DIR}/code/webapp" run dev -- \
  --port "${E2E_VITE_PORT}" --host 0.0.0.0 &>/tmp/vite-e2e-"${LETTER}".log &
echo "$!" > "${PID_FILE}"

# Wait for Vite to be ready
RETRIES=20
until curl -s "http://localhost:${E2E_VITE_PORT}" &>/dev/null; do
  RETRIES=$((RETRIES - 1))
  if [ "$RETRIES" -eq 0 ]; then
    echo "❌ Vite E2E did not start in time (see /tmp/vite-e2e-${LETTER}.log)"
    exit 1
  fi
  sleep 1
done
echo "✅ Vite E2E ready"

# ── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  ✅ E2E stack for ${WS_NAME} is ready"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  Open Cypress (interactive):"
echo "    make cypress WORKSPACE=${WS_NAME}"
echo ""
echo "  Run Cypress headless:"
echo "    make cypress-run WORKSPACE=${WS_NAME}"
echo ""
echo "  Stop when done:"
echo "    make e2e-stop WORKSPACE=${WS_NAME}"
echo ""
