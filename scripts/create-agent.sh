#!/bin/bash
set -euo pipefail

# ---------------------------------------------------------------------------
# create-agent.sh — Add a new agent clone to an existing dev-lab setup
#
# Usage:
#   ./scripts/create-agent.sh
#   ./scripts/create-agent.sh --branch=feature/066-my-feature
# ---------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

BRANCH="main"
REPO="https://github.com/pakodiazdev/sushigo.git"
LETTERS=(a b c d e f g h)
BASE_API_PORT=8001
BASE_VITE_PORT=5171

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
mkdir -p "${ROOT_DIR}/agents"

NEXT_INDEX=-1
for i in "${!LETTERS[@]}"; do
  LETTER="${LETTERS[$i]}"
  if [ ! -d "${ROOT_DIR}/agents/sushigo-agent-${LETTER}" ]; then
    NEXT_INDEX=$i
    break
  fi
done

if [ "$NEXT_INDEX" -eq -1 ]; then
  echo "❌ All agent slots (a–h) are already in use."
  exit 1
fi

LETTER="${LETTERS[$NEXT_INDEX]}"
AGENT_NAME="sushigo-agent-${LETTER}"
AGENT_DIR="${ROOT_DIR}/agents/${AGENT_NAME}"
DB_NAME="sushigo_agent_${LETTER}"
APP_PORT=$((BASE_API_PORT + NEXT_INDEX))
VITE_PORT=$((BASE_VITE_PORT + NEXT_INDEX))

echo ""
echo "➕ Creating ${AGENT_NAME} (branch: ${BRANCH})"
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
git clone --branch "${BRANCH}" "${REPO}" "${AGENT_DIR}"
cd "${AGENT_DIR}"

# ── Configure .env ───────────────────────────────────────────────────────────
echo "⚙️  Configuring .env..."
cp code/api/.env.example code/api/.env
sed -i '' "s|^APP_URL=.*|APP_URL=http://127.0.0.1:${APP_PORT}|" code/api/.env
sed -i '' "s|^DB_HOST=.*|DB_HOST=$(sed_esc "${PG_HOST}")|" code/api/.env
sed -i '' "s|^DB_DATABASE=.*|DB_DATABASE=$(sed_esc "${DB_NAME}")|" code/api/.env
sed -i '' "s|^DB_USERNAME=.*|DB_USERNAME=$(sed_esc "${PG_USER}")|" code/api/.env
sed -i '' "s|^DB_PASSWORD=.*|DB_PASSWORD=$(sed_esc "${PG_PASS}")|" code/api/.env
# Set a unique cache prefix to avoid Redis key collisions between agents
if grep -q "^CACHE_PREFIX" code/api/.env; then
  sed -i '' "s|^CACHE_PREFIX=.*|CACHE_PREFIX=agent_${LETTER}_|" code/api/.env
else
  echo "CACHE_PREFIX=agent_${LETTER}_" >> code/api/.env
fi

# Configure webapp .env (VITE_HMR_HOST intentionally unset → Vite auto-detects in local dev)
AGENT_LABEL="[$(echo "${LETTER}" | tr '[:lower:]' '[:upper:]')]"
cat > "${AGENT_DIR}/code/webapp/.env" <<EOF
VITE_API_URL=http://localhost:${APP_PORT}/api/v1
VITE_APP_ENV=development
VITE_TIME_FORMAT=12
VITE_DEV_DEBUGGER_START_HIDDEN=false
VITE_LOGIN_WITH_DEVDEBUG=true
VITE_DEV_LOGIN_ALLOWED_ENVIRONMENTS=dev,devtest
VITE_ENV_BADGE=🟢 
VITE_AGENT_LABEL=${AGENT_LABEL} 
EOF

cat > "${AGENT_DIR}/.env" <<EOF
APP_PORT=${APP_PORT}
VITE_PORT=${VITE_PORT}
DB_DATABASE=${DB_NAME}
AGENT_ROOT=${AGENT_DIR}
EOF

# Patch Procfile.dev with absolute paths so overmind works regardless of cwd
# (overmind creates its own tmux server which does not inherit the caller's cwd)
cat > "${AGENT_DIR}/Procfile.dev" <<'PROCFILE'
web:    php -S 0.0.0.0:${APP_PORT:-8000} -t ${AGENT_ROOT}/code/api/public
vite:   npm --prefix ${AGENT_ROOT}/code/webapp run dev -- --port ${VITE_PORT:-5173} --host 0.0.0.0
PROCFILE

# Mark Procfile.dev as skip-worktree: dev-lab owns it locally, git ignores changes
git -C "${AGENT_DIR}" update-index --skip-worktree Procfile.dev

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
cd "${AGENT_DIR}/code/api" && composer install --no-interaction --prefer-dist --no-progress --quiet --ignore-platform-req=php*
cd "${AGENT_DIR}/code/webapp" && npm install --silent

echo "🔑 Bootstrapping Laravel..."
cd "${AGENT_DIR}/code/api"
php artisan key:generate --ansi --quiet
php artisan migrate --force --quiet
php artisan db:seed --force --quiet

echo ""
echo "✅ ${AGENT_NAME} is ready"
echo ""
echo "  Start it:  ./scripts/init.sh ${AGENT_NAME#sushigo-}"
