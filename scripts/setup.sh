#!/bin/bash
set -euo pipefail

# ---------------------------------------------------------------------------
# setup.sh — Initialize the sushigo-dev-lab with N independent agent clones
#
# Usage:
#   ./scripts/setup.sh --agents=3
#   ./scripts/setup.sh --agents=2 --repo=git@github.com:pakodiazdev/sushigo.git
#   ./scripts/setup.sh --agents=2 --branch=feature/065-my-feature
# ---------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

AGENTS=1
BRANCH="main"
REPO="https://github.com/pakodiazdev/sushigo.git"
LETTERS=(a b c d e f g h)

PG_USER="${POSTGRES_USER:-admin}"
PG_PASS="${POSTGRES_PASSWORD:-admin}"
PG_HOST="${POSTGRES_HOST:-127.0.0.1}"
PG_PORT="${POSTGRES_HOST_PORT:-5432}"
export PGPASSWORD="${PG_PASS}"
pg() { psql -h "${PG_HOST}" -p "${PG_PORT}" -U "${PG_USER}" "$@"; }
# Escape values for use as sed replacement strings (&, \, and the | delimiter)
sed_esc() { printf '%s' "$1" | sed 's/\\/\\\\/g' | sed 's/[&|]/\\&/g'; }

# ── Argument parsing ────────────────────────────────────────────────────────
for arg in "$@"; do
  case $arg in
    --agents=*) AGENTS="${arg#*=}" ;;
    --branch=*) BRANCH="${arg#*=}" ;;
    --repo=*)   REPO="${arg#*=}" ;;
    *) echo "Unknown argument: $arg"; exit 1 ;;
  esac
done

if ! [[ "$AGENTS" =~ ^[1-8]$ ]]; then
  echo "❌ --agents must be between 1 and 8 (got: ${AGENTS})"
  exit 1
fi

# ── Prerequisite check ──────────────────────────────────────────────────────
check_cmd() {
  if ! command -v "$1" &>/dev/null; then
    echo "❌ Required tool not found: $1"
    echo "   Install: $2"
    exit 1
  fi
}

echo ""
echo "🔍 Checking prerequisites..."
check_cmd git      "https://git-scm.com"
check_cmd php      "brew install php"
check_cmd composer "brew install composer"
check_cmd node     "brew install node"
check_cmd npm      "included with node"
check_cmd overmind "brew install overmind"
check_cmd docker   "https://www.docker.com/products/docker-desktop"
check_cmd psql     "brew install libpq && brew link libpq --force"
echo "✅ All prerequisites satisfied"

# ── Shared Docker services ──────────────────────────────────────────────────
echo ""
echo "🐳 Starting shared Docker services..."
docker compose -f "${ROOT_DIR}/docker-compose.yml" up -d

echo "⏳ Waiting for PostgreSQL to be ready..."
RETRIES=30
until docker compose -f "${ROOT_DIR}/docker-compose.yml" exec -T db \
  pg_isready -U "${PG_USER}" &>/dev/null; do
  RETRIES=$((RETRIES - 1))
  if [ "$RETRIES" -eq 0 ]; then
    echo "❌ PostgreSQL did not become ready in time"
    exit 1
  fi
  sleep 1
done
echo "✅ PostgreSQL ready"

# ── Agent creation loop ─────────────────────────────────────────────────────
mkdir -p "${ROOT_DIR}/agents"

BASE_API_PORT=8001
BASE_VITE_PORT=5171

for i in $(seq 0 $((AGENTS - 1))); do
  LETTER="${LETTERS[$i]}"
  AGENT_NAME="sushigo-agent-${LETTER}"
  AGENT_DIR="${ROOT_DIR}/agents/${AGENT_NAME}"
  DB_NAME="sushigo_agent_${LETTER}"
  APP_PORT=$((BASE_API_PORT + i))
  VITE_PORT=$((BASE_VITE_PORT + i))

  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  Setting up agent-${LETTER} (port ${APP_PORT} / ${VITE_PORT})"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

  if [ -d "${AGENT_DIR}" ]; then
    if [ ! -f "${AGENT_DIR}/code/api/.env" ]; then
      # Partial setup: dir exists but .env is missing — previous run failed mid-way.
      # Reuse the existing clone and continue with configuration (skip clone step).
      echo "  ⚠️  Partial setup detected (code/api/.env missing) — resuming configuration"
      cd "${AGENT_DIR}"
      # fall through to configure .env, install deps, bootstrap Laravel
    else
      echo "  ⚠️  Directory exists — updating branch and dependencies"
      cd "${AGENT_DIR}"
      git fetch origin

      # Use --ff-only to avoid silently discarding local commits
      if git rev-parse "origin/${BRANCH}" &>/dev/null 2>&1; then
        git checkout "${BRANCH}" 2>/dev/null || git checkout -b "${BRANCH}" "origin/${BRANCH}"
        if ! git pull --ff-only origin "${BRANCH}" 2>/dev/null; then
          echo "  ⚠️  Cannot fast-forward agent-${LETTER} (local commits present) — skipping git update"
        fi
      else
        echo "  ℹ️  Branch ${BRANCH} not found on remote — staying on current branch"
      fi

      echo "  📚 Updating PHP dependencies..."
      cd "${AGENT_DIR}/code/api"
      composer install --no-interaction --prefer-dist --no-progress --quiet --ignore-platform-req=php*

      echo "  📦 Updating Node dependencies..."
      cd "${AGENT_DIR}/code/webapp"
      npm install --silent

      echo "  🛠  Running migrations (schema may have changed)..."
      cd "${AGENT_DIR}/code/api"
      php artisan migrate --force --quiet
      # Ensure AGENT_ROOT is present and Procfile.dev uses absolute paths
      if ! grep -q "^AGENT_ROOT=" "${AGENT_DIR}/.env"; then
        echo "AGENT_ROOT=${AGENT_DIR}" >> "${AGENT_DIR}/.env"
      fi
      cat > "${AGENT_DIR}/Procfile.dev" <<'PROCFILE'
web:    php -S 0.0.0.0:${APP_PORT:-8000} -t ${AGENT_ROOT}/code/api/public
vite:   npm --prefix ${AGENT_ROOT}/code/webapp run dev -- --port ${VITE_PORT:-5173} --host 0.0.0.0
PROCFILE
      git -C "${AGENT_DIR}" update-index --skip-worktree Procfile.dev
      echo "  ✅ agent-${LETTER} updated"
      continue
    fi
  fi

  if [ ! -d "${AGENT_DIR}" ]; then
    echo "  📦 Cloning sushigo on branch ${BRANCH}..."
    git clone --branch "${BRANCH}" "${REPO}" "${AGENT_DIR}"
  fi
  cd "${AGENT_DIR}"

  # Configure .env
  echo "  ⚙️  Configuring .env..."
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

  # Create database
  echo "  🗄️  Creating database ${DB_NAME}..."
  CREATE_OUTPUT="$(pg -d postgres -c "CREATE DATABASE ${DB_NAME};" 2>&1)" || true
  if echo "${CREATE_OUTPUT}" | grep -q "already exists"; then
    echo "  ℹ️  Database already exists — skipping"
  elif echo "${CREATE_OUTPUT}" | grep -qi "error\|fatal\|permission"; then
    echo "❌ Failed to create database: ${CREATE_OUTPUT}"
    exit 1
  fi

  # Install dependencies
  echo "  📚 Installing PHP dependencies..."
  cd "${AGENT_DIR}/code/api"
  composer install --no-interaction --prefer-dist --no-progress --quiet --ignore-platform-req=php*

  echo "  📦 Installing Node dependencies..."
  cd "${AGENT_DIR}/code/webapp"
  npm install --silent

  # Bootstrap Laravel
  echo "  🔑 Generating app key..."
  cd "${AGENT_DIR}/code/api"
  php artisan key:generate --ansi --quiet

  echo "  🛠  Running migrations and seeders..."
  php artisan migrate --force --quiet
  php artisan db:seed --force --quiet

  echo "  ✅ agent-${LETTER} ready"
done

# ── Summary ─────────────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  ✅ Setup complete — ${AGENTS} agent(s) ready"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
printf "  %-10s %-35s %-35s %s\n" "Agent" "Backend" "Frontend" "Database"
printf "  %-10s %-35s %-35s %s\n" "─────" "───────" "────────" "────────"

for i in $(seq 0 $((AGENTS - 1))); do
  LETTER="${LETTERS[$i]}"
  APP_PORT=$((BASE_API_PORT + i))
  VITE_PORT=$((BASE_VITE_PORT + i))
  printf "  %-10s %-35s %-35s %s\n" \
    "agent-${LETTER}" \
    "http://127.0.0.1:${APP_PORT}" \
    "http://localhost:${VITE_PORT}" \
    "sushigo_agent_${LETTER}"
done

echo ""
echo "  Next steps:"
echo "    Start one agent:   ./scripts/init.sh agent-a"
echo "    Start all agents:  ./scripts/init.sh"
echo "    Add another agent: ./scripts/create-agent.sh"
echo ""
