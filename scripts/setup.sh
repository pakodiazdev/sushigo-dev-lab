#!/bin/bash
set -euo pipefail

# ---------------------------------------------------------------------------
# setup.sh — Initialize the sushigo-dev-lab with N independent workspace clones
#
# Usage:
#   ./scripts/setup.sh --workspaces=3
#   ./scripts/setup.sh --workspaces=2 --repo=git@github.com:pakodiazdev/sushigo.git
#   ./scripts/setup.sh --workspaces=2 --branch=feature/065-my-feature
# ---------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Load tools.env (versions + port config)
if [ -f "${ROOT_DIR}/tools.env" ]; then
  source "${ROOT_DIR}/tools.env"
fi

WORKSPACES=1
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
    --workspaces=*) WORKSPACES="${arg#*=}" ;;
    --branch=*) BRANCH="${arg#*=}" ;;
    --repo=*)   REPO="${arg#*=}" ;;
    *) echo "Unknown argument: $arg"; exit 1 ;;
  esac
done

if ! [[ "$WORKSPACES" =~ ^[1-8]$ ]]; then
  echo "❌ --workspaces must be between 1 and 8 (got: ${WORKSPACES})"
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

# ── Workspace creation loop ─────────────────────────────────────────────────
mkdir -p "${ROOT_DIR}/workspaces"

for i in $(seq 0 $((WORKSPACES - 1))); do
  LETTER="${LETTERS[$i]}"
  WS_NAME="sushigo-${LETTER}"
  WS_DIR="${ROOT_DIR}/workspaces/${WS_NAME}"
  DB_NAME="sushigo_ws_${LETTER}"
  LETTER_UPPER="$(echo "${LETTER}" | tr '[:lower:]' '[:upper:]')"
  _slot_api_var="API_PORT_${LETTER_UPPER}"
  _slot_vite_var="VITE_PORT_${LETTER_UPPER}"
  _slot_label_var="AGENT_LABEL_${LETTER_UPPER}"
  APP_PORT="${!_slot_api_var:-$((8001 + i))}"
  VITE_PORT="${!_slot_vite_var:-$((5171 + i))}"
  WS_LABEL="${!_slot_label_var:-[${LETTER_UPPER}]}"
  ISSUE_NUM=$(echo "${BRANCH}" | grep -oE '[0-9]+' | head -1 || true)
  [ -n "${ISSUE_NUM}" ] && WS_LABEL="${WS_LABEL%]}:#${ISSUE_NUM}]"

  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  Setting up sushigo-${LETTER} (port ${APP_PORT} / ${VITE_PORT})"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

  if [ -d "${WS_DIR}" ]; then
    if [ ! -f "${WS_DIR}/code/api/.env" ]; then
      # Partial setup: dir exists but .env is missing — previous run failed mid-way.
      # Reuse the existing clone and continue with configuration (skip clone step).
      echo "  ⚠️  Partial setup detected (code/api/.env missing) — resuming configuration"
      cd "${WS_DIR}"
      # fall through to configure .env, install deps, bootstrap Laravel
    else
      echo "  ⚠️  Directory exists — updating branch and dependencies"
      cd "${WS_DIR}"
      git fetch origin

      # Use --ff-only to avoid silently discarding local commits
      if git rev-parse "origin/${BRANCH}" &>/dev/null 2>&1; then
        git checkout "${BRANCH}" 2>/dev/null || git checkout -b "${BRANCH}" "origin/${BRANCH}"
        if ! git pull --ff-only origin "${BRANCH}" 2>/dev/null; then
          echo "  ⚠️  Cannot fast-forward sushigo-${LETTER} (local commits present) — skipping git update"
        fi
      else
        echo "  ℹ️  Branch ${BRANCH} not found on remote — staying on current branch"
      fi

      echo "  📚 Updating PHP dependencies..."
      cd "${WS_DIR}/code/api"
      composer install --no-interaction --prefer-dist --no-progress --quiet --ignore-platform-req=php

      echo "  📦 Updating Node dependencies..."
      cd "${WS_DIR}/code/webapp"
      npm install --silent

      echo "  🛠  Running migrations (schema may have changed)..."
      cd "${WS_DIR}/code/api"
      php artisan migrate --force --quiet

      echo "  📖 Generating Swagger docs..."
      php artisan l5-swagger:generate --quiet
      # Ensure WORKSPACE_ROOT is present and Procfile.dev uses absolute paths
      if ! grep -q "^WORKSPACE_ROOT=" "${WS_DIR}/.env"; then
        echo "WORKSPACE_ROOT=${WS_DIR}" >> "${WS_DIR}/.env"
      fi
      cat > "${WS_DIR}/Procfile.dev" <<'PROCFILE'
web:    php -S 0.0.0.0:${APP_PORT:-8000} -t ${WORKSPACE_ROOT}/code/api/public
vite:   npm --prefix ${WORKSPACE_ROOT}/code/webapp run dev -- --port ${VITE_PORT:-5173} --host 0.0.0.0
PROCFILE
      git -C "${WS_DIR}" ls-files --error-unmatch Procfile.dev &>/dev/null 2>&1 && \
        git -C "${WS_DIR}" update-index --skip-worktree Procfile.dev || true
      echo "  ✅ sushigo-${LETTER} updated"
      continue
    fi
  fi

  if [ ! -d "${WS_DIR}" ]; then
    echo "  📦 Cloning sushigo on branch ${BRANCH}..."
    git clone --branch "${BRANCH}" "${REPO}" "${WS_DIR}"
  fi
  cd "${WS_DIR}"

  # Configure .env
  echo "  ⚙️  Configuring .env..."
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
  git -C "${WS_DIR}" ls-files --error-unmatch Procfile.dev &>/dev/null 2>&1 && \
    git -C "${WS_DIR}" update-index --skip-worktree Procfile.dev || true

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
  cd "${WS_DIR}/code/api"
  composer install --no-interaction --prefer-dist --no-progress --quiet --ignore-platform-req=php

  echo "  📦 Installing Node dependencies..."
  cd "${WS_DIR}/code/webapp"
  npm install --silent

  # Bootstrap Laravel
  echo "  🔑 Generating app key..."
  cd "${WS_DIR}/code/api"
  php artisan key:generate --ansi --quiet

  echo "  🔐 Generating Passport OAuth keys..."
  php artisan passport:keys --force --quiet

  echo "  🛠  Running migrations and seeders..."
  php artisan migrate --force --quiet
  php artisan db:seed --force --quiet

  echo "  📖 Generating Swagger docs..."
  php artisan l5-swagger:generate --quiet

  echo "  ✅ sushigo-${LETTER} ready"
done

# ── Summary ─────────────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  ✅ Setup complete — ${WORKSPACES} workspace(s) ready"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
printf "  %-12s %-35s %-35s %s\n" "Workspace" "Backend" "Frontend" "Database"
printf "  %-12s %-35s %-35s %s\n" "─────────" "───────" "────────" "────────"

for i in $(seq 0 $((WORKSPACES - 1))); do
  LETTER="${LETTERS[$i]}"
  LETTER_UPPER="$(echo "${LETTER}" | tr '[:lower:]' '[:upper:]')"
  _slot_api_var="API_PORT_${LETTER_UPPER}"
  _slot_vite_var="VITE_PORT_${LETTER_UPPER}"
  APP_PORT="${!_slot_api_var:-$((8001 + i))}"
  VITE_PORT="${!_slot_vite_var:-$((5171 + i))}"
  printf "  %-12s %-35s %-35s %s\n" \
    "sushigo-${LETTER}" \
    "http://127.0.0.1:${APP_PORT}" \
    "http://localhost:${VITE_PORT}" \
    "sushigo_ws_${LETTER}"
done

echo ""
echo "  Next steps:"
echo "    Start one workspace:   ./scripts/init.sh sushigo-a"
echo "    Start all workspaces:  ./scripts/init.sh"
echo "    Add another workspace: ./scripts/create-workspace.sh"
echo ""
