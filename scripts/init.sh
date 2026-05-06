#!/bin/bash
set -euo pipefail

# ---------------------------------------------------------------------------
# init.sh — Start one or all agents
#
# Single agent (foreground): delegates to init-agent-workspace.sh, which loads
# .env, validates prerequisites, and starts Overmind interactively.
#
# All agents (background): sources each agent's .env directly and calls
# `overmind start -D` (daemon mode). init-agent-workspace.sh is intentionally
# bypassed here because it runs Overmind in foreground mode only, and there is
# no standard way to daemonize it via the script. If init-agent-workspace.sh
# gains additional setup steps in the future, replicate them here.
#
# Usage:
#   ./scripts/init.sh               Start all agents (background)
#   ./scripts/init.sh agent-a       Start one agent (foreground, Overmind output)
# ---------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
AGENTS_DIR="${ROOT_DIR}/agents"

TARGET="${1:-}"

PG_USER="${POSTGRES_USER:-admin}"

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

  if [ ! -f "${AGENT_DIR}/init-agent-workspace.sh" ]; then
    echo "❌ init-agent-workspace.sh not found in ${AGENT_DIR}"
    echo "   Make sure the sushigo clone has the script at its root."
    exit 1
  fi

  echo "🚀 Starting ${TARGET}..."
  cd "${AGENT_DIR}"
  exec bash init-agent-workspace.sh
fi

# ── All agents (background) ──────────────────────────────────────────────────
AGENT_DIRS=("${AGENTS_DIR}"/sushigo-agent-*)

if [ ${#AGENT_DIRS[@]} -eq 0 ] || [ ! -d "${AGENT_DIRS[0]}" ]; then
  echo "❌ No agents found in ${AGENTS_DIR}"
  echo "   Run ./scripts/setup.sh --agents=2 first."
  exit 1
fi

echo "🚀 Starting ${#AGENT_DIRS[@]} agent(s) in background..."
echo ""

for AGENT_DIR in "${AGENT_DIRS[@]}"; do
  AGENT_NAME="$(basename "${AGENT_DIR}")"

  if [ ! -f "${AGENT_DIR}/init-agent-workspace.sh" ]; then
    echo "  ⚠️  Skipping ${AGENT_NAME} — init-agent-workspace.sh not found"
    continue
  fi

  if [ ! -f "${AGENT_DIR}/Procfile.dev" ]; then
    echo "  ⚠️  Skipping ${AGENT_NAME} — Procfile.dev not found"
    continue
  fi

  source "${AGENT_DIR}/.env" 2>/dev/null || true

  echo "  ▶ ${AGENT_NAME}"
  echo "    Backend  → http://127.0.0.1:${APP_PORT:-?}"
  echo "    Frontend → http://localhost:${VITE_PORT:-?}"

  # init-agent-workspace.sh runs Overmind in foreground; use -D for daemon mode
  # after sourcing .env so port variables are available to the child process.
  (
    set -o allexport
    source "${AGENT_DIR}/.env" 2>/dev/null || true
    set +o allexport
    cd "${AGENT_DIR}"
    if ! command -v overmind &>/dev/null; then
      echo "  ❌ Overmind not found — brew install overmind"
      exit 1
    fi
    overmind start -f Procfile.dev -D
  ) &

  unset APP_PORT VITE_PORT
done

echo ""
echo "All agents started. To inspect a specific agent:"
echo "  cd agents/<agent-name> && overmind connect web"
echo "  cd agents/<agent-name> && overmind stop"
