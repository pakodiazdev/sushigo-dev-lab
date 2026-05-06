#!/bin/bash
set -euo pipefail

# ---------------------------------------------------------------------------
# reset-agent-db.sh — Drop, recreate and re-seed one agent's database
#
# Usage:
#   ./scripts/reset-agent-db.sh agent-a
#   ./scripts/reset-agent-db.sh a
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
  echo "Usage: $0 <agent-name>"
  echo "Example: $0 agent-a"
  exit 1
fi

# Normalize: accept "a" or "agent-a"
if [[ "$TARGET" != agent-* ]] && [[ "$TARGET" != sushigo-* ]]; then
  TARGET="agent-${TARGET}"
fi
if [[ "$TARGET" == sushigo-* ]]; then
  TARGET="${TARGET#sushigo-}"
fi

# Validate: must be agent-[a-h]
if ! [[ "$TARGET" =~ ^agent-[a-h]$ ]]; then
  echo "❌ Invalid agent name: ${TARGET}"
  echo "   Expected: agent-a through agent-h"
  exit 1
fi

AGENT_DIR="${ROOT_DIR}/agents/sushigo-${TARGET}"
DB_NAME="sushigo_${TARGET//-/_}"

if [ ! -d "${AGENT_DIR}" ]; then
  echo "❌ Agent not found: sushigo-${TARGET}"
  echo "   Available agents:"
  ls "${ROOT_DIR}/agents" 2>/dev/null | sed 's/^/     /' || echo "     (none)"
  exit 1
fi

echo ""
echo "🗑  Resetting database for sushigo-${TARGET}"
echo "   Database: ${DB_NAME}"
echo ""

# ── Check shared services ────────────────────────────────────────────────────
if ! pg -d postgres -c '\q' &>/dev/null; then
  echo "❌ Cannot connect to PostgreSQL at ${PG_HOST}:${PG_PORT}"
  echo "   Run: docker compose up -d"
  exit 1
fi

# ── Drop and recreate ─────────────────────────────────────────────────────────
echo "  Dropping ${DB_NAME}..."
pg -d postgres \
  -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname='${DB_NAME}';" \
  &>/dev/null || true
pg -d postgres -c "DROP DATABASE IF EXISTS ${DB_NAME};" &>/dev/null

echo "  Creating ${DB_NAME}..."
pg -d postgres -c "CREATE DATABASE ${DB_NAME};" &>/dev/null

# ── Migrate and seed ─────────────────────────────────────────────────────────
echo "  Migrating..."
cd "${AGENT_DIR}/code/api"
php artisan migrate --force --quiet

echo "  Seeding..."
php artisan db:seed --force --quiet

echo ""
echo "✅ sushigo-${TARGET} database reset complete"
