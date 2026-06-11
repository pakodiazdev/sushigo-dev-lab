#!/bin/bash
set -euo pipefail

# ---------------------------------------------------------------------------
# cypress.sh — Run Cypress against the E2E stack for one workspace
#
# Resolves the running container name and Vite port, then launches
# Cypress with CYPRESS_baseUrl and CYPRESS_container set correctly.
#
# Usage:
#   ./scripts/cypress.sh sushigo-a          # interactive GUI
#   ./scripts/cypress.sh a --run            # headless
# ---------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

TARGET="${1:-}"
MODE="${2:-}"

if [ -z "$TARGET" ]; then
  echo "Usage: $0 <workspace> [--run]"
  echo "Example: $0 sushigo-a"
  echo "Example: $0 sushigo-a --run"
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
LETTER_UPPER="$(echo "${LETTER}" | tr '[:lower:]' '[:upper:]')"
WS_NAME="sushigo-${LETTER}"
WS_DIR="${ROOT_DIR}/workspaces/${WS_NAME}"

# Load tools.env for port config
if [ -f "${ROOT_DIR}/tools.env" ]; then
  # shellcheck source=/dev/null
  source "${ROOT_DIR}/tools.env"
fi

_e2e_api_var="E2E_API_PORT_${LETTER_UPPER}"
_e2e_vite_var="E2E_VITE_PORT_${LETTER_UPPER}"
E2E_API_PORT="${!_e2e_api_var:-$((8900 + $(echo "${LETTER}" | tr 'a-h' '12345678')))}"
E2E_VITE_PORT="${!_e2e_vite_var:-$((5180 + $(echo "${LETTER}" | tr 'a-h' '12345678')))}"

# Find the running E2E container for this workspace
CONTAINER="$(docker ps --format '{{.Names}}' | grep "e2e-api-${LETTER}" | head -1 || true)"

if [ -z "${CONTAINER}" ]; then
  echo "❌ E2E stack for ${WS_NAME} is not running."
  echo "   Start it first: make e2e WORKSPACE=${WS_NAME}"
  exit 1
fi

RECORD_ACTIVE=""
if [ "${MODE}" = "--run" ] && [ -n "${CYPRESS_RECORD_KEY:-}" ]; then
  RECORD_ACTIVE="yes"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Cypress — ${WS_NAME}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Base URL:  http://localhost:${E2E_VITE_PORT}"
echo "  Container: ${CONTAINER}"
if [ -n "${RECORD_ACTIVE}" ]; then
  echo "  Recording: ✅ Cypress Cloud"
fi
echo ""

if [ "${MODE}" = "--run" ]; then
  if [ -n "${RECORD_ACTIVE}" ]; then
    E2E_CONTAINER="${CONTAINER}" \
    VITE_PORT="${E2E_VITE_PORT}" \
    E2E_API_PORT="${E2E_API_PORT}" \
    CYPRESS_RECORD_KEY="${CYPRESS_RECORD_KEY}" \
      npm --prefix "${WS_DIR}/code/webapp" run cypress:run:devlab -- --record
  else
    E2E_CONTAINER="${CONTAINER}" \
    VITE_PORT="${E2E_VITE_PORT}" \
    E2E_API_PORT="${E2E_API_PORT}" \
      npm --prefix "${WS_DIR}/code/webapp" run cypress:run:devlab
  fi
else
  E2E_CONTAINER="${CONTAINER}" \
  VITE_PORT="${E2E_VITE_PORT}" \
  E2E_API_PORT="${E2E_API_PORT}" \
    npm --prefix "${WS_DIR}/code/webapp" run cypress:open:devlab
fi
