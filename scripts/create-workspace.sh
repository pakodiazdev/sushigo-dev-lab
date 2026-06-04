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

BRANCH="main"
REPO="https://github.com/pakodiazdev/sushigo.git"
LETTERS=(a b c d e f g h)

# Load tools.env (versions + port config)
if [ -f "${ROOT_DIR}/tools.env" ]; then
  source "${ROOT_DIR}/tools.env"
fi

PG_USER="${POSTGRES_USER:-admin}"
PG_PASS="${POSTGRES_PASSWORD:-admin}"
PG_HOST="${POSTGRES_HOST:-127.0.0.1}"
PG_PORT="${POSTGRES_HOST_PORT:-5432}"
export PGPASSWORD="${PG_PASS}"
pg() { psql -h "${PG_HOST}" -p "${PG_PORT}" -U "${PG_USER}" "$@"; }
sed_esc() { printf '%s' "$1" | sed 's/\\/\\\\/g' | sed 's/[&|]/\\&/g'; }

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

# ── Clone ────────────────────────────────────────────────────────────────────
echo "📦 Cloning sushigo on branch ${BRANCH}..."
git clone --branch "${BRANCH}" "${REPO}" "${WS_DIR}"
cd "${WS_DIR}"

# ── Configure .env ───────────────────────────────────────────────────────────
echo "⚙️  Configuring .env..."
cp code/api/.env.example code/api/.env
sed -i '' "s|^APP_URL=.*|APP_URL=http://127.0.0.1:${APP_PORT}|" code/api/.env
sed -i '' "s|^DB_HOST=.*|DB_HOST=$(sed_esc "${PG_HOST}")|" code/api/.env
sed -i '' "s|^DB_DATABASE=.*|DB_DATABASE=$(sed_esc "${DB_NAME}")|" code/api/.env
sed -i '' "s|^DB_USERNAME=.*|DB_USERNAME=$(sed_esc "${PG_USER}")|" code/api/.env
sed -i '' "s|^DB_PASSWORD=.*|DB_PASSWORD=$(sed_esc "${PG_PASS}")|" code/api/.env
# Set a unique cache/queue prefix to avoid Redis key collisions between workspaces
if grep -q "^CACHE_PREFIX" code/api/.env; then
  sed -i '' "s|^CACHE_PREFIX=.*|CACHE_PREFIX=ws_${LETTER}_|" code/api/.env
else
  echo "CACHE_PREFIX=ws_${LETTER}_" >> code/api/.env
fi
# Enable dev-debug login for local development
sed -i '' "s|^LOGIN_WITH_DEVDEBUG=.*|LOGIN_WITH_DEVDEBUG=true|" code/api/.env
sed -i '' "s|^DEV_LOGIN_ALLOWED_ENVIRONMENTS=.*|DEV_LOGIN_ALLOWED_ENVIRONMENTS=dev,devtest,local|" code/api/.env
# Enable clock simulation for local development
sed -i '' "s|^CLOCK_SIMULATION_ENABLED=.*|CLOCK_SIMULATION_ENABLED=true|" code/api/.env
# Allow the workspace's Vite dev-server port in CORS (both localhost and 127.0.0.1)
CORS_ORIGINS="http://localhost:${VITE_PORT},http://127.0.0.1:${VITE_PORT}"
if grep -q "^CORS_ALLOWED_ORIGINS" code/api/.env; then
  sed -i '' "s|^CORS_ALLOWED_ORIGINS=.*|CORS_ALLOWED_ORIGINS=${CORS_ORIGINS}|" code/api/.env
else
  echo "CORS_ALLOWED_ORIGINS=${CORS_ORIGINS}" >> code/api/.env
fi

# Configure webapp .env (VITE_HMR_HOST intentionally unset → Vite auto-detects in local dev)
cat > "${WS_DIR}/code/webapp/.env" <<EOF
VITE_API_URL=http://localhost:${APP_PORT}/api/v1
VITE_APP_ENV=dev
VITE_TIME_FORMAT=12
VITE_DEV_DEBUGGER_START_HIDDEN=false
VITE_LOGIN_WITH_DEVDEBUG=true
VITE_DEV_LOGIN_ALLOWED_ENVIRONMENTS=dev,devtest
VITE_ENV_BADGE=🟢 
VITE_AGENT_LABEL=${WS_LABEL} 
VITE_GIT_BRANCH=${BRANCH}
EOF

cat > "${WS_DIR}/.env" <<EOF
APP_PORT=${APP_PORT}
VITE_PORT=${VITE_PORT}
DB_DATABASE=${DB_NAME}
WORKSPACE_ROOT=${WS_DIR}
EOF

# Patch Procfile.dev with absolute paths so overmind works regardless of cwd
# (overmind creates its own tmux server which does not inherit the caller's cwd)
cat > "${WS_DIR}/Procfile.dev" <<'PROCFILE'
web:    php -S 0.0.0.0:${APP_PORT:-8000} -t ${WORKSPACE_ROOT}/code/api/public
vite:   npm --prefix ${WORKSPACE_ROOT}/code/webapp run dev -- --port ${VITE_PORT:-5173} --host 0.0.0.0
PROCFILE

# Mark Procfile.dev as skip-worktree: dev-lab owns it locally, git ignores changes
git -C "${WS_DIR}" update-index --skip-worktree Procfile.dev

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
echo "📚 Installing dependencies..."
cd "${WS_DIR}/code/api" && composer install --no-interaction --prefer-dist --no-progress --quiet --ignore-platform-req=php
cd "${WS_DIR}/code/webapp" && npm install --silent

echo "🔑 Bootstrapping Laravel..."
cd "${WS_DIR}/code/api"
php artisan key:generate --ansi --quiet

echo "🔐 Generating Passport OAuth keys..."
php artisan passport:keys --force --quiet

php artisan migrate --force --quiet
php artisan db:seed --force --quiet

echo "📖 Generating Swagger docs..."
php artisan l5-swagger:generate --quiet

echo ""
echo "✅ ${WS_NAME} is ready"
echo ""
echo "  Start it:  ./scripts/init.sh ${WS_NAME}"
