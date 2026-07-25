#!/bin/bash
set -euo pipefail

# ---------------------------------------------------------------------------
# create-workspace.sh — Add a new workspace clone to an existing dev-lab setup
#
# Usage:
#   ./scripts/create-workspace.sh
#   ./scripts/create-workspace.sh --branch=feature/066-my-feature
# ---------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

source "${SCRIPT_DIR}/lib/workspace-bootstrap.sh"

BRANCH="main"
REPO="https://github.com/pakodiazdev/sushigo.git"
LETTERS=(a b c d e f g h)

# Load tools.env (versions + port config)
if [ -f "${ROOT_DIR}/tools.env" ]; then
  source "${ROOT_DIR}/tools.env"
fi

# Load dev-lab .env (local secrets — gitignored, never committed)
if [ -f "${ROOT_DIR}/.env" ]; then
  source "${ROOT_DIR}/.env"
fi

PG_USER="${POSTGRES_USER:-admin}"
PG_PASS="${POSTGRES_PASSWORD:-admin}"
PG_HOST="${POSTGRES_HOST:-127.0.0.1}"
PG_PORT="${POSTGRES_HOST_PORT:-5432}"
export PGPASSWORD="${PG_PASS}"
pg() { psql -h "${PG_HOST}" -p "${PG_PORT}" -U "${PG_USER}" "$@"; }

for arg in "$@"; do
  case $arg in
    --branch=*) BRANCH="${arg#*=}" ;;
    --repo=*)   REPO="${arg#*=}" ;;
    *) echo "Unknown argument: $arg"; exit 1 ;;
  esac
done

# ── Detect next available slot ──────────────────────────────────────────────
mkdir -p "${ROOT_DIR}/workspaces"

NEXT_INDEX=-1
for i in "${!LETTERS[@]}"; do
  LETTER="${LETTERS[$i]}"
  if [ ! -d "${ROOT_DIR}/workspaces/sushigo-${LETTER}" ]; then
    NEXT_INDEX=$i
    break
  fi
done

if [ "$NEXT_INDEX" -eq -1 ]; then
  echo "❌ All workspace slots (a–h) are already in use."
  exit 1
fi

LETTER="${LETTERS[$NEXT_INDEX]}"
WS_NAME="sushigo-${LETTER}"
WS_DIR="${ROOT_DIR}/workspaces/${WS_NAME}"
DB_NAME="sushigo_ws_${LETTER}"
DB_NAME_TEST="${DB_NAME}_test"
LETTER_UPPER="$(echo "${LETTER}" | tr '[:lower:]' '[:upper:]')"
_slot_api_var="API_PORT_${LETTER_UPPER}"
_slot_vite_var="VITE_PORT_${LETTER_UPPER}"
_slot_label_var="AGENT_LABEL_${LETTER_UPPER}"
APP_PORT="${!_slot_api_var:-$((8001 + NEXT_INDEX))}"
VITE_PORT="${!_slot_vite_var:-$((5171 + NEXT_INDEX))}"
WS_LABEL="${!_slot_label_var:-[${LETTER_UPPER}]}"
ISSUE_NUM=$(echo "${BRANCH}" | grep -oE '[0-9]+' | head -1 || true)
[ -n "${ISSUE_NUM}" ] && WS_LABEL="${WS_LABEL%]}:#${ISSUE_NUM}]"

echo ""
echo "➕ Creating ${WS_NAME} (branch: ${BRANCH})"
echo "   Backend  → http://127.0.0.1:${APP_PORT}"
echo "   Frontend → http://localhost:${VITE_PORT}"
echo "   Database → ${DB_NAME}"
echo ""

# ── Check shared services are up ────────────────────────────────────────────
if ! docker compose -f "${ROOT_DIR}/docker-compose.yml" exec -T db \
  pg_isready -U "${PG_USER}" &>/dev/null; then
  echo "⚠️  Shared services not running. Starting them..."
  docker compose -f "${ROOT_DIR}/docker-compose.yml" up -d
  echo "⏳ Waiting for PostgreSQL..."
  RETRIES=20
  until docker compose -f "${ROOT_DIR}/docker-compose.yml" exec -T db \
    pg_isready -U "${PG_USER}" &>/dev/null; do
    RETRIES=$((RETRIES - 1))
    [ "$RETRIES" -eq 0 ] && echo "❌ PostgreSQL not ready" && exit 1
    sleep 1
  done
fi

# ── PHPUnit test database ───────────────────────────────────────────────────
# Each workspace gets its own test database (sushigo_ws_<letter>_test), mirroring
# the per-workspace dev database. A single shared mydb_test previously caused
# SQLSTATE[40P01] deadlocks when two workspaces ran `php artisan test` at the
# same time — RefreshDatabase's schema setup isn't protected by per-test
# transactions the way individual test data is.
echo "🗄️  Ensuring PHPUnit test database (${DB_NAME_TEST}) exists..."
CREATE_OUTPUT="$(pg -d postgres -c "CREATE DATABASE ${DB_NAME_TEST};" 2>&1)" || true
if echo "${CREATE_OUTPUT}" | grep -q "already exists"; then
  echo "ℹ️  ${DB_NAME_TEST} already exists — skipping"
elif echo "${CREATE_OUTPUT}" | grep -qi "error\|fatal\|permission"; then
  echo "❌ Failed to create ${DB_NAME_TEST}: ${CREATE_OUTPUT}"
  exit 1
fi

# ── Clone ────────────────────────────────────────────────────────────────────
echo "📦 Cloning sushigo on branch ${BRANCH}..."
git clone --branch "${BRANCH}" "${REPO}" "${WS_DIR}"
cd "${WS_DIR}"

# ── Configure .env ───────────────────────────────────────────────────────────
echo "⚙️  Configuring .env..."
configure_api_env "${WS_DIR}" "${LETTER}" "${APP_PORT}" "${VITE_PORT}" "${DB_NAME}" "${PG_HOST}" "${PG_USER}" "${PG_PASS}"
configure_webapp_env "${WS_DIR}" "${APP_PORT}" "${WS_LABEL}"
configure_workspace_env "${WS_DIR}" "${APP_PORT}" "${VITE_PORT}" "${DB_NAME}" "${SONAR_TOKEN:-}"

write_procfile "${WS_DIR}"
mark_procfile_skip_worktree "${WS_DIR}"

# ── Create database ───────────────────────────────────────────────────────────
echo "🗄️  Creating database ${DB_NAME}..."
CREATE_OUTPUT="$(pg -d postgres -c "CREATE DATABASE ${DB_NAME};" 2>&1)" || true
if echo "${CREATE_OUTPUT}" | grep -q "already exists"; then
  echo "ℹ️  Database already exists — skipping"
elif echo "${CREATE_OUTPUT}" | grep -qi "error\|fatal\|permission"; then
  echo "❌ Failed to create database: ${CREATE_OUTPUT}"
  exit 1
fi

# ── Install and bootstrap ─────────────────────────────────────────────────────
install_deps "${WS_DIR}"
bootstrap_laravel "${WS_DIR}" "${DB_NAME_TEST}"

echo ""
echo "✅ ${WS_NAME} is ready"
echo ""
echo "  Start it:  ./scripts/init.sh ${WS_NAME}"
