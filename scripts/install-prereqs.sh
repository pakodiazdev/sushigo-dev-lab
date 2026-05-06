#!/bin/bash
set -euo pipefail

# ---------------------------------------------------------------------------
# install-prereqs.sh — Install missing prerequisites via Homebrew
#
# Installs only what is missing. Safe to re-run (idempotent).
# Tools that require manual installation (git, docker) are skipped
# with a clear message.
#
# Versions are read from tools.env at the repo root.
# CLI flags override tools.env values.
#
# Usage:
#   ./scripts/install-prereqs.sh              # uses tools.env defaults
#   ./scripts/install-prereqs.sh --php=8.2 --node=20
#   make install
#   make install PHP=8.2 NODE=20
# ---------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Load defaults from tools.env
PHP_VERSION="8.3"
NODE_VERSION="22"
if [ -f "${ROOT_DIR}/tools.env" ]; then
  # shellcheck source=/dev/null
  source "${ROOT_DIR}/tools.env"
fi

# CLI flags override tools.env
for arg in "$@"; do
  case "$arg" in
    --php=*)  PHP_VERSION="${arg#--php=}" ;;
    --node=*) NODE_VERSION="${arg#--node=}" ;;
    *) echo "Unknown argument: $arg"; echo "Usage: $0 [--php=X.Y] [--node=X]"; exit 1 ;;
  esac
done

INSTALLED=0
SKIPPED=0
MANUAL=0

ok()     { echo "  ✅  $1"; }
install(){ echo "  📦  Installing $1..."; }
skip()   { echo "  ✔️   $1 already installed — skipping"; SKIPPED=$((SKIPPED + 1)); }
manual() { echo "  ⚠️   $1 — must be installed manually"; echo "       $2"; MANUAL=$((MANUAL + 1)); }

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  sushigo-dev-lab — install prerequisites"
echo "  PHP: ${PHP_VERSION}   Node: ${NODE_VERSION}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# ── Homebrew check ────────────────────────────────────────────────────────────
if ! command -v brew &>/dev/null; then
  echo "  ❌  Homebrew not found — all brew-based installs require it"
  echo "       Install: /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
  echo ""
  exit 1
fi

ok "brew   $(brew --version | head -1 | awk '{print $2}')"
echo ""

# ── Manual-only tools ─────────────────────────────────────────────────────────
echo "  Manual installs (skipping)"
echo "  ──────────────────────────"

if ! command -v git &>/dev/null; then
  manual "git" "xcode-select --install   (or https://git-scm.com)"
else
  skip "git   $(git --version | awk '{print $3}')"
fi

if ! command -v docker &>/dev/null; then
  manual "docker" "https://www.docker.com/products/docker-desktop"
else
  skip "docker   $(docker --version | awk '{print $3}' | tr -d ',')"
fi

echo ""

# ── PHP stack ─────────────────────────────────────────────────────────────────
echo "  PHP stack"
echo "  ─────────"

PHP_TARGET_MAJOR=$(echo "$PHP_VERSION" | cut -d. -f1)
PHP_TARGET_MINOR=$(echo "$PHP_VERSION" | cut -d. -f2)
PHP_BREW_FORMULA="php@${PHP_VERSION}"

if command -v php &>/dev/null; then
  PHP_CURRENT=$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')
  PHP_CURRENT_MAJOR=$(echo "$PHP_CURRENT" | cut -d. -f1)
  PHP_CURRENT_MINOR=$(echo "$PHP_CURRENT" | cut -d. -f2)
  if [ "$PHP_CURRENT_MAJOR" -eq "$PHP_TARGET_MAJOR" ] && [ "$PHP_CURRENT_MINOR" -eq "$PHP_TARGET_MINOR" ]; then
    skip "php   ${PHP_CURRENT}"
  else
    install "php@${PHP_VERSION} (current: ${PHP_CURRENT})"
    brew install "${PHP_BREW_FORMULA}"
    brew link "${PHP_BREW_FORMULA}" --force --overwrite
    ok "php@${PHP_VERSION}   installed and linked"
    INSTALLED=$((INSTALLED + 1))
  fi
else
  install "php@${PHP_VERSION}"
  brew install "${PHP_BREW_FORMULA}"
  brew link "${PHP_BREW_FORMULA}" --force --overwrite
  ok "php@${PHP_VERSION}   installed and linked"
  INSTALLED=$((INSTALLED + 1))
fi

if command -v composer &>/dev/null; then
  skip "composer   $(composer --version 2>/dev/null | awk '{print $3}')"
else
  install "composer"
  brew install composer
  ok "composer   installed"
  INSTALLED=$((INSTALLED + 1))
fi

echo ""

# ── Node stack ────────────────────────────────────────────────────────────────
echo "  Node stack"
echo "  ──────────"

# Homebrew formula: node@22, node@20, etc. (major version only)
NODE_BREW_FORMULA="node@${NODE_VERSION}"

if command -v node &>/dev/null; then
  NODE_CURRENT_MAJOR=$(node --version | tr -d 'v' | cut -d. -f1)
  if [ "$NODE_CURRENT_MAJOR" -eq "$NODE_VERSION" ]; then
    skip "node   $(node --version)"
  else
    install "node@${NODE_VERSION} (current: v${NODE_CURRENT_MAJOR})"
    brew install "${NODE_BREW_FORMULA}"
    brew link "${NODE_BREW_FORMULA}" --force --overwrite
    ok "node@${NODE_VERSION}   installed and linked"
    INSTALLED=$((INSTALLED + 1))
  fi
else
  install "node@${NODE_VERSION}"
  brew install "${NODE_BREW_FORMULA}"
  brew link "${NODE_BREW_FORMULA}" --force --overwrite
  ok "node@${NODE_VERSION}   installed and linked"
  INSTALLED=$((INSTALLED + 1))
fi

if command -v npm &>/dev/null; then
  skip "npm   $(npm --version)   (bundled with node)"
else
  echo "  ⚠️   npm not found after node install — check PATH"
fi

echo ""

# ── Process management ────────────────────────────────────────────────────────
echo "  Process management"
echo "  ───────────────────"

if command -v overmind &>/dev/null; then
  skip "overmind   $(overmind --version 2>/dev/null | head -1)"
else
  install "overmind"
  brew install overmind
  ok "overmind   installed"
  INSTALLED=$((INSTALLED + 1))
fi

if command -v tmux &>/dev/null; then
  skip "tmux   $(tmux -V | awk '{print $2}')   (used by overmind internally)"
else
  install "tmux"
  brew install tmux
  ok "tmux   installed"
  INSTALLED=$((INSTALLED + 1))
fi

echo ""

# ── Database client ───────────────────────────────────────────────────────────
echo "  Database client"
echo "  ───────────────"

if command -v psql &>/dev/null; then
  skip "psql   $(psql --version | awk '{print $3}')"
else
  install "libpq (psql)"
  brew install libpq
  brew link libpq --force
  ok "psql   installed and linked"
  INSTALLED=$((INSTALLED + 1))
fi

echo ""

# ── Summary ───────────────────────────────────────────────────────────────────
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [ "$MANUAL" -gt 0 ]; then
  echo "  ⚠️   ${MANUAL} tool(s) require manual installation (see above)"
fi
if [ "$INSTALLED" -gt 0 ]; then
  echo "  ✅  ${INSTALLED} tool(s) installed,  ${SKIPPED} already present"
  echo ""
  echo "  Run 'make doctor' to verify all prerequisites."
else
  echo "  ✅  Nothing to install — ${SKIPPED} tool(s) already present"
fi
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
