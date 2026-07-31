#!/bin/bash
set -euo pipefail

# ---------------------------------------------------------------------------
# update-workspaces.sh — Switch every workspace clone to main and pull latest
#
# Iterates over workspaces/sushigo-*/, skipping (never discarding) any
# workspace with uncommitted changes. Clean workspaces are checked out to
# main and fast-forward pulled.
#
# Usage:
#   ./scripts/update-workspaces.sh
# ---------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
WORKSPACES_DIR="${ROOT_DIR}/workspaces"

updated=0
skipped=0
failed=0

sync_workspace() {
  local ws_dir="$1"
  local ws_name
  ws_name="$(basename "${ws_dir}")"

  if [ -n "$(cd "${ws_dir}" && git status --porcelain)" ]; then
    echo "⚠️  ${ws_name}  →  skipped (uncommitted changes)"
    skipped=$((skipped + 1))
    return
  fi

  if ! (cd "${ws_dir}" && git fetch origin) &>/dev/null; then
    echo "❌ ${ws_name}  →  failed (git fetch error)"
    failed=$((failed + 1))
    return
  fi

  if ! (cd "${ws_dir}" && git checkout main) &>/dev/null; then
    echo "❌ ${ws_name}  →  failed (no local main branch)"
    failed=$((failed + 1))
    return
  fi

  local old_sha new_sha
  old_sha="$(cd "${ws_dir}" && git rev-parse --short HEAD)"

  if ! (cd "${ws_dir}" && git pull --ff-only origin main) &>/dev/null; then
    echo "❌ ${ws_name}  →  failed (non-fast-forward — needs manual rebase/merge)"
    failed=$((failed + 1))
    return
  fi

  new_sha="$(cd "${ws_dir}" && git rev-parse --short HEAD)"
  echo "✅ ${ws_name}  →  main updated (${old_sha}..${new_sha})"
  updated=$((updated + 1))
}

if [ ! -d "${WORKSPACES_DIR}" ] || [ -z "$(ls -d "${WORKSPACES_DIR}"/sushigo-*/ 2>/dev/null)" ]; then
  echo "❌ No workspaces found in ${WORKSPACES_DIR}"
  exit 1
fi

for ws_dir in "${WORKSPACES_DIR}"/sushigo-*/; do
  sync_workspace "${ws_dir}"
done

echo ""
echo "${updated} updated, ${skipped} skipped, ${failed} failed"
