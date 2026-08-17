#!/bin/bash
set -euo pipefail

# ---------------------------------------------------------------------------
# workspace-status.sh — Pure helpers for scripts/status.sh
#
# Sourced by status.sh. These helpers only ever shell out to short-lived,
# read-only commands (grep, git rev-parse) — never to Overmind or any other
# process supervision — so every state they can produce is reproducible in
# Bats with plain fixture input/output instead of a live Overmind session.
# The actual `overmind status` invocation stays in status.sh itself.
# ---------------------------------------------------------------------------

# read_env_value <env_file> <key>
# Prints the value of KEY=... from env_file, or an empty string if the file
# is unreadable or the key is absent. Never fails the caller.
read_env_value() {
  local env_file="$1"
  local key="$2"

  [ -r "${env_file}" ] || { printf ''; return 0; }
  grep -m1 "^${key}=" "${env_file}" 2>/dev/null | cut -d'=' -f2- || printf ''
}

# workspace_branch <ws_dir>
# Prints ws_dir's own current git branch, or "?" if ws_dir does not host its
# own git repository. workspaces/ lives inside the dev-lab checkout itself
# (only gitignored, which does not stop repository discovery) — a plain
# `git -C ws_dir rev-parse` on a workspace whose clone is missing or
# corrupted silently walks up and returns the *dev-lab's* branch instead of
# failing, so callers must not rev-parse a workspace directly without this
# guard first.
workspace_branch() {
  local ws_dir="$1"
  local toplevel

  toplevel="$(git -C "${ws_dir}" rev-parse --show-toplevel 2>/dev/null)" || { printf '?'; return 0; }
  if [ "${toplevel}" != "$(cd "${ws_dir}" 2>/dev/null && pwd -P)" ]; then
    printf '?'
    return 0
  fi

  git -C "${ws_dir}" rev-parse --abbrev-ref HEAD 2>/dev/null || printf '?'
}

# truncate_field <value> <max_width>
# Shortens value to max_width characters, appending an ellipsis when cut.
# Used to keep long git branch names from blowing out the status table.
truncate_field() {
  local value="$1"
  local max="$2"

  if [ "${#value}" -gt "${max}" ]; then
    printf '%s…' "${value:0:$((max - 1))}"
  else
    printf '%s' "${value}"
  fi
}

# classify_process_table <overmind_status_stdout>
# Given the stdout of a successful (`overmind status`, exit 0) call, prints
# "STATE|PROC_SUMMARY". STATE is one of: running, degraded, stopped,
# stale-socket (used here for the degenerate case of zero parsed process
# rows — a connected socket that describes nothing is not trustworthy).
# PROC_SUMMARY is a space-joined list of "process:status" pairs.
classify_process_table() {
  local table="$1"
  local proc _pid pstatus
  local running=0
  local total=0
  local summary=()

  while IFS= read -r line; do
    read -r proc _pid pstatus <<<"${line}"
    if [ -z "${proc}" ] || [ "${proc}" = "PROCESS" ]; then
      continue
    fi
    total=$((total + 1))
    summary+=("${proc}:${pstatus}")
    if [ "${pstatus}" = "running" ]; then
      running=$((running + 1))
    fi
  done <<<"${table}"

  local state
  if [ "${total}" -eq 0 ]; then
    state="stale-socket"
    summary=("no processes reported")
  elif [ "${running}" -eq "${total}" ]; then
    state="running"
  elif [ "${running}" -eq 0 ]; then
    state="stopped"
  else
    state="degraded"
  fi

  local joined
  joined="$(IFS=' '; echo "${summary[*]}")"
  printf '%s|%s\n' "${state}" "${joined}"
}
