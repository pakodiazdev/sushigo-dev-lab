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

source "${SCRIPT_DIR}/lib/workspace-bootstrap.sh"

# Load tools.env (versions + port config)
if [ -f "${ROOT_DIR}/tools.env" ]; then
  source "${ROOT_DIR}/tools.env"
fi

# Load dev-lab .env (local secrets — gitignored, never committed)
if [ -f "${ROOT_DIR}/.env" ]; then
  source "${ROOT_DIR}/.env"
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
  DB_NAME_TEST="${DB_NAME}_test"
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

      install_deps "${WS_DIR}"

      echo "  🛠  Running migrations (schema may have changed)..."
      (cd "${WS_DIR}/code/api" && php artisan migrate --force --quiet)

      echo "  📖 Generating Swagger docs..."
      (cd "${WS_DIR}/code/api" && php artisan l5-swagger:generate --quiet) || \
        echo "  ⚠️  Swagger doc generation failed — continuing without docs (see sushigo repo for the fix)"
      # Ensure WORKSPACE_ROOT is present and Procfile.dev uses absolute paths
      if ! grep -q "^WORKSPACE_ROOT=" "${WS_DIR}/.env"; then
        echo "WORKSPACE_ROOT=${WS_DIR}" >> "${WS_DIR}/.env"
      fi
      # Propagate dev-lab secrets (upsert). Written as SONAR_TOKEN_API / SONAR_TOKEN_WEBAPP
      # to match the keys the workspace's own tooling (e.g. /sonar-review) expects — same
      # keys the fresh-workspace path below writes.
      if [ -n "${SONAR_TOKEN:-}" ]; then
        for SONAR_KEY in SONAR_TOKEN_API SONAR_TOKEN_WEBAPP; do
          if grep -q "^${SONAR_KEY}=" "${WS_DIR}/.env"; then
            sed -i '' "s|^${SONAR_KEY}=.*|${SONAR_KEY}=${SONAR_TOKEN}|" "${WS_DIR}/.env"
          else
            echo "${SONAR_KEY}=${SONAR_TOKEN}" >> "${WS_DIR}/.env"
          fi
        done
      fi
      write_procfile "${WS_DIR}"
      mark_procfile_skip_worktree "${WS_DIR}"
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
  configure_api_env "${WS_DIR}" "${LETTER}" "${APP_PORT}" "${VITE_PORT}" "${DB_NAME}" "${PG_HOST}" "${PG_USER}" "${PG_PASS}"
  configure_webapp_env "${WS_DIR}" "${APP_PORT}" "${WS_LABEL}"
  configure_workspace_env "${WS_DIR}" "${APP_PORT}" "${VITE_PORT}" "${DB_NAME}" "${SONAR_TOKEN:-}"

  write_procfile "${WS_DIR}"
  mark_procfile_skip_worktree "${WS_DIR}"

  # Create database
  echo "  🗄️  Creating database ${DB_NAME}..."
  CREATE_OUTPUT="$(pg -d postgres -c "CREATE DATABASE ${DB_NAME};" 2>&1)" || true
  if echo "${CREATE_OUTPUT}" | grep -q "already exists"; then
    echo "  ℹ️  Database already exists — skipping"
  elif echo "${CREATE_OUTPUT}" | grep -qi "error\|fatal\|permission"; then
    echo "❌ Failed to create database: ${CREATE_OUTPUT}"
    exit 1
  fi

  # Create PHPUnit test database — isolated per workspace to avoid the
  # SQLSTATE[40P01] deadlocks a single shared mydb_test caused when multiple
  # workspaces ran `php artisan test` concurrently.
  echo "  🗄️  Creating test database ${DB_NAME_TEST}..."
  CREATE_OUTPUT="$(pg -d postgres -c "CREATE DATABASE ${DB_NAME_TEST};" 2>&1)" || true
  if echo "${CREATE_OUTPUT}" | grep -q "already exists"; then
    echo "  ℹ️  Test database already exists — skipping"
  elif echo "${CREATE_OUTPUT}" | grep -qi "error\|fatal\|permission"; then
    echo "❌ Failed to create test database: ${CREATE_OUTPUT}"
    exit 1
  fi

  install_deps "${WS_DIR}"
  bootstrap_laravel "${WS_DIR}" "${DB_NAME_TEST}"

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
