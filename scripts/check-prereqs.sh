#!/bin/bash
set -euo pipefail

# ---------------------------------------------------------------------------
# check-prereqs.sh — Verify all tools required by sushigo-dev-lab
#
# Usage:
#   ./scripts/check-prereqs.sh
#   make doctor
# ---------------------------------------------------------------------------

PASS=0
FAIL=0

ok()   { echo "  ✅  $1"; PASS=$((PASS + 1)); }
fail() { echo "  ❌  $1"; echo "       Install: $2"; FAIL=$((FAIL + 1)); }
info() { echo "       $1"; }


echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  sushigo-dev-lab — prerequisite check"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# ── Core tools ──────────────────────────────────────────────────────────────
echo "  Core tools"
echo "  ──────────"

if command -v git &>/dev/null; then
  ok "git   $(git --version | awk '{print $3}')"
else
  fail "git" "https://git-scm.com"
fi

if command -v docker &>/dev/null; then
  DOCKER_VER=$(docker --version 2>/dev/null | awk '{print $3}' | tr -d ',')
  if docker info &>/dev/null 2>&1; then
    ok "docker   ${DOCKER_VER} (daemon running)"
  else
    fail "docker   ${DOCKER_VER} — daemon not running" "Open Docker Desktop"
  fi
else
  fail "docker" "https://www.docker.com/products/docker-desktop"
fi

echo ""

# ── PHP stack ────────────────────────────────────────────────────────────────
echo "  PHP stack"
echo "  ─────────"

if command -v php &>/dev/null; then
  PHP_VER=$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')
  PHP_MAJOR=$(php -r 'echo PHP_MAJOR_VERSION;')
  PHP_MINOR=$(php -r 'echo PHP_MINOR_VERSION;')
  if [ "$PHP_MAJOR" -gt 8 ] || ([ "$PHP_MAJOR" -eq 8 ] && [ "$PHP_MINOR" -ge 2 ]); then
    ok "php   ${PHP_VER}"
  else
    fail "php   ${PHP_VER} — need 8.2+" "brew install php"
  fi
else
  fail "php" "brew install php"
fi

if command -v composer &>/dev/null; then
  COMPOSER_VER=$(composer --version 2>/dev/null | awk '{print $3}')
  ok "composer   ${COMPOSER_VER}"
else
  fail "composer" "brew install composer"
  info "Or: curl -sS https://getcomposer.org/installer | php && mv composer.phar /usr/local/bin/composer"
fi

echo ""

# ── Node stack ───────────────────────────────────────────────────────────────
echo "  Node stack"
echo "  ──────────"

if command -v node &>/dev/null; then
  NODE_VER=$(node --version)
  NODE_MAJOR=$(node --version | tr -d 'v' | cut -d. -f1)
  if [ "$NODE_MAJOR" -ge 18 ]; then
    ok "node   ${NODE_VER}"
  else
    fail "node   ${NODE_VER} — need 18+" "brew install node"
  fi
else
  fail "node" "brew install node"
fi

if command -v npm &>/dev/null; then
  ok "npm   $(npm --version)"
else
  fail "npm" "included with node — brew install node"
fi

echo ""

# ── Process management ───────────────────────────────────────────────────────
echo "  Process management"
echo "  ───────────────────"

if command -v overmind &>/dev/null; then
  ok "overmind   $(overmind --version 2>/dev/null | head -1)"
else
  fail "overmind" "brew install overmind"
  info "Overmind manages web + vite processes per agent (Procfile supervisor)"
fi

if command -v tmux &>/dev/null; then
  ok "tmux   $(tmux -V | awk '{print $2}')   (optional — used by overmind internally)"
else
  echo "  ⚠️   tmux — not found (optional, used by overmind)"
  info "Install: brew install tmux"
fi

echo ""

# ── Database client ──────────────────────────────────────────────────────────
echo "  Database client"
echo "  ───────────────"

PSQL_BIN=""
if command -v psql &>/dev/null; then
  PSQL_BIN="$(command -v psql)"
else
  PSQL_BIN="$(find /usr/local/Cellar/libpq /opt/homebrew/Cellar/libpq \
    -name "psql" 2>/dev/null | sort -r | head -1 || true)"
fi

if [ -n "$PSQL_BIN" ]; then
  PSQL_VER=$("$PSQL_BIN" --version 2>/dev/null | awk '{print $3}')
  if command -v psql &>/dev/null; then
    ok "psql   ${PSQL_VER}"
  else
    ok "psql   ${PSQL_VER}   (found at ${PSQL_BIN})"
    echo "  ⚠️   psql not in PATH — run:"
    info "brew link libpq --force"
  fi
else
  fail "psql" "brew install libpq && brew link libpq --force"
fi

echo ""

# ── Docker connectivity ──────────────────────────────────────────────────────
echo "  Docker services"
echo "  ───────────────"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

if docker compose -f "${ROOT_DIR}/docker-compose.yml" ps db 2>/dev/null | grep -q "Up\|running"; then
  DB_STATUS=$(docker compose -f "${ROOT_DIR}/docker-compose.yml" ps --format "{{.Status}}" db 2>/dev/null)
  if echo "$DB_STATUS" | grep -q "healthy"; then
    ok "PostgreSQL   ${DB_STATUS}"
  else
    echo "  ⚠️   PostgreSQL — ${DB_STATUS}"
    info "Run: make up"
  fi

  REDIS_STATUS=$(docker compose -f "${ROOT_DIR}/docker-compose.yml" ps --format "{{.Status}}" redis 2>/dev/null)
  if echo "$REDIS_STATUS" | grep -q "healthy"; then
    ok "Redis   ${REDIS_STATUS}"
  else
    echo "  ⚠️   Redis — ${REDIS_STATUS}"
    info "Run: make up"
  fi

  MAILPIT_STATUS=$(docker compose -f "${ROOT_DIR}/docker-compose.yml" ps --format "{{.Status}}" mailpit 2>/dev/null)
  if echo "$MAILPIT_STATUS" | grep -q "healthy"; then
    ok "Mailpit   ${MAILPIT_STATUS}"
  else
    echo "  ⚠️   Mailpit — ${MAILPIT_STATUS}"
    info "Run: make up"
  fi
else
  echo "  ⚠️   Shared services not running"
  info "Run: make up"
fi

echo ""

# ── Summary ──────────────────────────────────────────────────────────────────
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [ "$FAIL" -eq 0 ]; then
  echo "  ✅  All prerequisites satisfied (${PASS} checks passed)"
  echo ""
  echo "  Ready to run:  ./scripts/setup.sh --workspaces=2"
else
  echo "  ❌  ${FAIL} prerequisite(s) missing — install them before running setup.sh"
  echo "     ${PASS} check(s) passed"
  if [ "$FAIL" -gt 0 ]; then
    echo ""
    echo "  Quick install (macOS):"
    echo "    brew install php composer node overmind libpq"
    echo "    brew link libpq --force"
  fi
fi
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

exit "$FAIL"
