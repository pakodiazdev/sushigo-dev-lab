#!/bin/bash
set -euo pipefail

# ---------------------------------------------------------------------------
# init.sh — Start one or all workspaces
#
# Single workspace (foreground): delegates to init-agent-workspace.sh, which loads
# .env, validates prerequisites, and starts Overmind interactively.
#
# All workspaces (background): sources each workspace's .env directly and calls
# `overmind start -D` (daemon mode). init-agent-workspace.sh is intentionally
# bypassed here because it runs Overmind in foreground mode only, and there is
# no standard way to daemonize it via the script. If init-agent-workspace.sh
# gains additional setup steps in the future, replicate them here.
#
# Usage:
#   ./scripts/init.sh                  Start all workspaces (background)
#   ./scripts/init.sh sushigo-a        Start one workspace (foreground, Overmind output)
#   ./scripts/init.sh --count=2        Start only the first N workspaces (background)
# ---------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
WS_DIR_BASE="${ROOT_DIR}/workspaces"

TARGET=""
COUNT=""

for arg in "$@"; do
  case "$arg" in
    --count=*) COUNT="${arg#--count=}" ;;
    *) TARGET="$arg" ;;
  esac
done

PG_USER="${POSTGRES_USER:-admin}"

# ── Shared helper: write Procfile.dev with absolute paths ────────────────────
# Usage: write_procfile <ws_dir>
# Reads WORKSPACE_ROOT, APP_PORT, VITE_PORT from <ws_dir>/.env.
write_procfile() {
  local ws_dir="$1"
  cat > "${ws_dir}/Procfile.dev" <<'PROCFILE'
web:    php -S 0.0.0.0:${APP_PORT:-8000} -t ${WORKSPACE_ROOT}/code/api/public
vite:   npm --prefix ${WORKSPACE_ROOT}/code/webapp run dev -- --port ${VITE_PORT:-5173} --host 0.0.0.0
PROCFILE
}

# ── Ensure shared services are running ──────────────────────────────────────
if ! docker compose -f "${ROOT_DIR}/docker-compose.yml" exec -T db \
  pg_isready -U "${PG_USER}" &>/dev/null 2>&1; then
  echo "🐳 Shared services not running — starting them..."
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

# ── Single agent (foreground) ────────────────────────────────────────────────
if [ -n "$TARGET" ]; then
  # Accept "a", "agent-a", or "sushigo-agent-a"
  if [[ "$TARGET" != agent-* ]] && [[ "$TARGET" != sushigo-* ]]; then
    TARGET="agent-${TARGET}"
  fi
  if [[ "$TARGET" != sushigo-* ]]; then
    TARGET="sushigo-${TARGET}"
  fi

  AGENT_DIR="${AGENTS_DIR}/${TARGET}"

  if [ ! -d "${AGENT_DIR}" ]; then
    echo "❌ Agent not found: ${TARGET}"
    echo "   Available agents:"
    ls "${AGENTS_DIR}" 2>/dev/null | sed 's/^/     /' || echo "     (none)"
    exit 1
  fi

  echo "🚀 Starting ${TARGET}..."
  set -o allexport
  source "${AGENT_DIR}/.env" 2>/dev/null || true
  set +o allexport
  write_procfile "${AGENT_DIR}"
  cd "${AGENT_DIR}"
  exec overmind start -f "${AGENT_DIR}/Procfile.dev"
fi

# ── All workspaces (background) ────────────────────────────────────────────

# Count existing configured workspaces
EXISTING=0
for d in "${WS_DIR_BASE}"/sushigo-*/; do
  [ -f "${d}.env" ] && EXISTING=$((EXISTING + 1))
done

if [ -n "$COUNT" ] && [ "$COUNT" -gt "$EXISTING" ]; then
  # Explicit count exceeds existing workspaces — set up the missing ones
  echo "⚙️  Requested ${COUNT} workspace(s) but only ${EXISTING} configured — running setup for missing ones..."
  "${SCRIPT_DIR}/setup.sh" --workspaces="${COUNT}"
elif [ -z "$COUNT" ] && [ "$EXISTING" -eq 0 ]; then
  # No count specified and no workspaces exist — set up at least 1
  echo "⚙️  No workspaces found — running setup for 1 workspace..."
  "${SCRIPT_DIR}/setup.sh" --workspaces=1
fi

WS_DIRS=("${WS_DIR_BASE}"/sushigo-*)

echo "🚀 Starting ${#WS_DIRS[@]} workspace(s) in background..."
echo ""

STARTED=0
for WS_DIR in "${WS_DIRS[@]}"; do
  if [ -n "$COUNT" ] && [ "$STARTED" -ge "$COUNT" ]; then
    break
  fi
  WS_NAME="$(basename "${WS_DIR}")"

  if [ ! -f "${WS_DIR}/.env" ]; then
    echo "  ⚠️  Skipping ${WS_NAME} — .env not found (run setup.sh first)"
    continue
  fi

  source "${WS_DIR}/.env" 2>/dev/null || true

  echo "  ▶ ${WS_NAME}"
  echo "    Backend  → http://127.0.0.1:${APP_PORT:-?}"
  echo "    Frontend → http://localhost:${VITE_PORT:-?}"

  # Always regenerate Procfile.dev from the lab — never rely on the repo's copy.
  write_procfile "${WS_DIR}"
  (
    set -o allexport
    source "${WS_DIR}/.env" 2>/dev/null || true
    set +o allexport
    cd "${WS_DIR}"
    overmind start -f "${WS_DIR}/Procfile.dev" -D
  ) &

  unset APP_PORT VITE_PORT WORKSPACE_ROOT
  STARTED=$((STARTED + 1))
done

echo ""
echo "All workspaces started. To inspect a specific workspace:"
echo "  cd workspaces/<ws-name> && overmind connect web   # attach to web process"
echo "  cd workspaces/<ws-name> && overmind quit          # stop all processes"
