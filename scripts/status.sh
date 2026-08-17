#!/bin/bash
set -euo pipefail
# A non-zero `overmind status` for one slot is expected input, not a script
# bug — it's always tested as an if/elif condition below, which set -e
# never treats as fatal, so the report still continues for the rest.

# ---------------------------------------------------------------------------
# status.sh — Reliable runtime overview of every workspace slot
#
# Reports, for slots a through h: git branch, APP_PORT, VITE_PORT, and a
# state derived from actually talking to Overmind — not from the mere
# existence of .overmind.sock, which survives both a clean `overmind quit`
# and an unclean crash of the Overmind master process.
#
# States:
#   unconfigured  no workspace directory / .env for this slot
#   stopped       no processes running (never started, or cleanly quit)
#   running       every process in the workspace's Procfile is running
#   degraded      some, but not all, processes are running
#   stale-socket  .overmind.sock exists but nothing answers on it
#
# Usage:
#   ./scripts/status.sh
# ---------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
WS_BASE="${ROOT_DIR}/workspaces"

# shellcheck source=lib/workspace-status.sh
source "${SCRIPT_DIR}/lib/workspace-status.sh"

# Without this, a missing `overmind` binary makes every configured, started
# workspace's `overmind status` call fail the same way a truly stale socket
# does — reporting a missing prerequisite as stale-socket would be
# misleading, so fail fast with a clear, actionable error instead.
if ! command -v overmind &>/dev/null; then
  echo "❌ Required tool not found: overmind"
  echo "   Install: brew install overmind"
  exit 1
fi

LETTERS=(a b c d e f g h)

COL_WS=11
COL_STATE=13
COL_BRANCH=28
COL_PORT=6

printf '%-*s  %-*s %-*s %-*s %-*s  %s\n' \
  "${COL_WS}" "WORKSPACE" "${COL_STATE}" "STATE" "${COL_BRANCH}" "BRANCH" \
  "${COL_PORT}" "APP" "${COL_PORT}" "VITE" "PROCESSES"

count_running=0
count_degraded=0
count_stopped=0
count_stale=0
count_unconfigured=0

for letter in "${LETTERS[@]}"; do
  ws_name="sushigo-${letter}"
  ws_dir="${WS_BASE}/${ws_name}"

  if [ ! -d "${ws_dir}" ] || [ ! -f "${ws_dir}/.env" ]; then
    state="unconfigured"
    branch="-"
    app_port="-"
    vite_port="-"
    processes="-"
    count_unconfigured=$((count_unconfigured + 1))
  else
    app_port="$(read_env_value "${ws_dir}/.env" "APP_PORT")"
    vite_port="$(read_env_value "${ws_dir}/.env" "VITE_PORT")"
    app_port="${app_port:-?}"
    vite_port="${vite_port:-?}"

    branch="$(workspace_branch "${ws_dir}")"
    branch="$(truncate_field "${branch}" "${COL_BRANCH}")"

    if [ ! -S "${ws_dir}/.overmind.sock" ]; then
      state="stopped"
      processes="not started"
      count_stopped=$((count_stopped + 1))
    elif status_output="$(cd "${ws_dir}" && overmind status 2>&1)"; then
      classified="$(classify_process_table "${status_output}")"
      state="${classified%%|*}"
      processes="${classified#*|}"
      case "${state}" in
        running) count_running=$((count_running + 1)) ;;
        degraded) count_degraded=$((count_degraded + 1)) ;;
        stopped) count_stopped=$((count_stopped + 1)) ;;
        stale-socket) count_stale=$((count_stale + 1)) ;;
      esac
    else
      state="stale-socket"
      processes="socket unresponsive"
      count_stale=$((count_stale + 1))
    fi
  fi

  printf '%-*s  %-*s %-*s %-*s %-*s  %s\n' \
    "${COL_WS}" "${ws_name}" "${COL_STATE}" "${state}" \
    "${COL_BRANCH}" "${branch}" "${COL_PORT}" "${app_port}" "${COL_PORT}" "${vite_port}" "${processes}"
done

echo ""
echo "${count_running} running · ${count_degraded} degraded · ${count_stopped} stopped · ${count_stale} stale-socket · ${count_unconfigured} unconfigured"
