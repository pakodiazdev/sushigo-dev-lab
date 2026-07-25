#!/bin/bash
set -euo pipefail

# ---------------------------------------------------------------------------
# delete-workspace.sh — Cleanly remove one workspace slot
#
# Stops its Overmind session and E2E stack (if running), drops its databases,
# and removes its directory. Does not touch shared Docker services or any
# other workspace.
#
# Usage:
#   ./scripts/delete-workspace.sh sushigo-a
#   ./scripts/delete-workspace.sh a
# ---------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

TARGET="${1:-}"

PG_USER="${POSTGRES_USER:-admin}"
PG_PASS="${POSTGRES_PASSWORD:-admin}"
PG_HOST="${POSTGRES_HOST:-127.0.0.1}"
PG_PORT="${POSTGRES_HOST_PORT:-5432}"
export PGPASSWORD="${PG_PASS}"
pg() { psql -h "${PG_HOST}" -p "${PG_PORT}" -U "${PG_USER}" "$@"; }

if [ -z "$TARGET" ]; then
  echo "Usage: $0 <workspace-name>"
  echo "Example: $0 sushigo-a"
  exit 1
fi

# Normalize: accept "a" or "sushigo-a" — extract the letter
if [[ "$TARGET" == sushigo-* ]]; then
  TARGET="${TARGET#sushigo-}"
fi

# Validate: must be a single letter a–h
if ! [[ "$TARGET" =~ ^[a-h]$ ]]; then
  echo "❌ Invalid workspace name: ${TARGET}"
  echo "   Expected: a through h, or sushigo-a through sushigo-h"
  exit 1
fi

WS_DIR="${ROOT_DIR}/workspaces/sushigo-${TARGET}"
DB_NAME="sushigo_ws_${TARGET}"
DB_NAME_TEST="${DB_NAME}_test"
DB_NAME_E2E="${DB_NAME}_e2e"

if [ ! -d "${WS_DIR}" ]; then
  echo "❌ Workspace not found: sushigo-${TARGET}"
  echo "   Available workspaces:"
  ls "${ROOT_DIR}/workspaces" 2>/dev/null | sed 's/^/     /' || echo "     (none)"
  exit 1
fi

echo ""
echo "🗑  Deleting workspace sushigo-${TARGET}"
echo "   Directory: ${WS_DIR}"
echo "   Databases: ${DB_NAME}, ${DB_NAME_TEST}, ${DB_NAME_E2E}"
echo ""

# ── Check shared services before making any destructive change ──────────────
if ! pg -d postgres -c '\q' &>/dev/null; then
  echo "❌ Cannot connect to PostgreSQL at ${PG_HOST}:${PG_PORT}"
  echo "   Run: docker compose up -d"
  exit 1
fi

# ── Stop Overmind if running ─────────────────────────────────────────────────
if [ -S "${WS_DIR}/.overmind.sock" ]; then
  echo "  ⏹  Stopping Overmind session..."
  if ! (cd "${WS_DIR}" && overmind quit) 2>/dev/null; then
    echo "  ⚠️  Failed to stop Overmind cleanly — workspace processes may still be running"
  fi
else
  echo "  ⏹  No running Overmind session found — skipping"
fi

# ── Stop E2E stack if running (container + Vite dev server) ─────────────────
# Must run before dropping ${DB_NAME_E2E} below, otherwise the e2e-api
# container can reconnect between pg_terminate_backend and DROP DATABASE.
"${SCRIPT_DIR}/stop-e2e.sh" "${TARGET}"

# ── Drop databases ────────────────────────────────────────────────────────────
for db in "${DB_NAME}" "${DB_NAME_TEST}" "${DB_NAME_E2E}"; do
  echo "  🗄️  Dropping ${db}..."
  pg -d postgres \
    -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname='${db}';" \
    &>/dev/null || true
  pg -d postgres -c "DROP DATABASE IF EXISTS ${db};" &>/dev/null
done

# ── Remove workspace directory ───────────────────────────────────────────────
echo "  🧹 Removing ${WS_DIR}..."
rm -rf "${WS_DIR}"

echo ""
echo "✅ sushigo-${TARGET} deleted"
echo "   Removed: ${WS_DIR}"
echo "   Dropped: ${DB_NAME}, ${DB_NAME_TEST}, ${DB_NAME_E2E}"
