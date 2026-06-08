#!/bin/bash
set -euo pipefail

# ---------------------------------------------------------------------------
# stop-e2e.sh — Stop the E2E stack for one workspace
#
# Kills the Vite E2E dev server and stops the e2e-api Docker container.
#
# Usage:
#   ./scripts/stop-e2e.sh sushigo-a
#   ./scripts/stop-e2e.sh a
# ---------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

TARGET="${1:-}"

if [ -z "$TARGET" ]; then
  echo "Usage: $0 <workspace>"
  echo "Example: $0 sushigo-a"
  exit 1
fi

# Normalize: accept "a" or "sushigo-a"
if [[ "$TARGET" == sushigo-* ]]; then
  TARGET="${TARGET#sushigo-}"
fi

if ! [[ "$TARGET" =~ ^[a-h]$ ]]; then
  echo "❌ Invalid workspace: ${TARGET} (expected a–h)"
  exit 1
fi

LETTER="${TARGET}"
WS_NAME="sushigo-${LETTER}"
CONTAINER="e2e-api-${LETTER}"
PID_FILE="${ROOT_DIR}/.e2e-vite-${LETTER}.pid"

echo ""
echo "⏹  Stopping E2E stack for ${WS_NAME}..."

# ── Stop Vite E2E ────────────────────────────────────────────────────────────
if [ -f "${PID_FILE}" ]; then
  VITE_PID="$(cat "${PID_FILE}")"
  if [[ "${VITE_PID}" =~ ^[0-9]+$ ]] && kill -0 "${VITE_PID}" 2>/dev/null; then
    kill "${VITE_PID}"
    echo "  ✅ Vite E2E stopped (PID ${VITE_PID})"
  else
    echo "  ℹ️  Vite E2E process not running"
  fi
  rm -f "${PID_FILE}"
else
  echo "  ℹ️  No Vite E2E PID file found"
fi

# ── Stop e2e-api container ───────────────────────────────────────────────────
if docker ps --format '{{.Names}}' | grep -q "${CONTAINER}"; then
  docker compose \
    -f "${ROOT_DIR}/docker-compose.yml" \
    -f "${ROOT_DIR}/docker-compose.e2e.yml" \
    stop "${CONTAINER}"
  echo "  ✅ Container ${CONTAINER} stopped"
else
  echo "  ℹ️  Container ${CONTAINER} was not running"
fi

echo ""
echo "✅ E2E stack for ${WS_NAME} stopped"
echo ""
