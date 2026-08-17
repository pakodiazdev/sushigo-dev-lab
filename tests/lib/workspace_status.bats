#!/usr/bin/env bats
# ---------------------------------------------------------------------------
# workspace_status.bats — Coverage for the pure helpers in
# scripts/lib/workspace-status.sh: read_env_value, truncate_field,
# workspace_branch and classify_process_table.
#
# The actual `overmind status` invocation lives in scripts/status.sh and is
# intentionally out of scope here — it shells out to a real Overmind socket
# and is side-effect heavy, not config-only. classify_process_table takes
# that command's captured stdout as plain text, so every state it can
# produce is reproducible here with literal fixture text instead of a live
# (and, in practice, hard to reproduce on demand) Overmind session.
# ---------------------------------------------------------------------------

bats_require_minimum_version 1.5.0

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"

  # shellcheck source=../../scripts/lib/workspace-status.sh
  source "${REPO_ROOT}/scripts/lib/workspace-status.sh"

  ENV_DIR="$(mktemp -d)"

  # A fake "dev-lab" outer repo with a workspaces/ subdirectory, mirroring
  # the real layout: workspaces/ is only gitignored, not outside the outer
  # repo, so git's own upward directory discovery can walk past a workspace
  # with no .git of its own and land on this outer repo instead.
  OUTER_REPO="$(mktemp -d)"
  git -C "${OUTER_REPO}" init -q
  git -C "${OUTER_REPO}" config user.email "test@example.com"
  git -C "${OUTER_REPO}" config user.name "Test"
  git -C "${OUTER_REPO}" commit -q --allow-empty -m "outer repo initial commit"
  git -C "${OUTER_REPO}" checkout -q -b lab-main
  mkdir -p "${OUTER_REPO}/workspaces/sushigo-a"
}

teardown() {
  rm -rf "${ENV_DIR}" "${OUTER_REPO}"
}

# --- read_env_value ------------------------------------------------------

@test "read_env_value returns the value for an existing key" {
  printf 'APP_PORT=8001\nVITE_PORT=5171\n' > "${ENV_DIR}/.env"

  run read_env_value "${ENV_DIR}/.env" "APP_PORT"
  [ "$status" -eq 0 ]
  [ "$output" = "8001" ]
}

@test "read_env_value returns empty for a missing key without failing" {
  printf 'APP_PORT=8001\n' > "${ENV_DIR}/.env"

  run read_env_value "${ENV_DIR}/.env" "VITE_PORT"
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}

@test "read_env_value returns empty for a nonexistent file without failing" {
  run read_env_value "${ENV_DIR}/does-not-exist.env" "APP_PORT"
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}

@test "read_env_value handles an empty (corrupt) env file" {
  : > "${ENV_DIR}/.env"

  run read_env_value "${ENV_DIR}/.env" "APP_PORT"
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}

@test "read_env_value only matches the key at line start" {
  printf 'VITE_APP_PORT=9999\nAPP_PORT=8001\n' > "${ENV_DIR}/.env"

  run read_env_value "${ENV_DIR}/.env" "APP_PORT"
  [ "$status" -eq 0 ]
  [ "$output" = "8001" ]
}

# --- truncate_field --------------------------------------------------------

@test "truncate_field leaves a short value unchanged" {
  run truncate_field "main" 28
  [ "$output" = "main" ]
}

@test "truncate_field leaves a value exactly at the limit unchanged" {
  run truncate_field "12345" 5
  [ "$output" = "12345" ]
}

@test "truncate_field shortens a long value and appends an ellipsis" {
  run truncate_field "feature/421-a-very-long-branch-name-indeed" 20
  [ "$output" = "feature/421-a-very-…" ]
  [ "${#output}" -eq 20 ]
}

# --- workspace_branch --------------------------------------------------------

@test "workspace_branch returns the branch for a workspace with its own git repo" {
  local ws_dir="${OUTER_REPO}/workspaces/sushigo-a"
  git -C "${ws_dir}" init -q
  git -C "${ws_dir}" config user.email "test@example.com"
  git -C "${ws_dir}" config user.name "Test"
  git -C "${ws_dir}" commit -q --allow-empty -m "workspace initial commit"
  git -C "${ws_dir}" checkout -q -b feature/421-workspace-branch

  run workspace_branch "${ws_dir}"
  [ "$status" -eq 0 ]
  [ "$output" = "feature/421-workspace-branch" ]
}

@test "workspace_branch returns ? instead of leaking the outer repo's branch" {
  # Regression test: workspaces/ lives inside this repo's own git checkout
  # (only gitignored). A workspace directory with no .git of its own must
  # never report the *outer* (dev-lab) repo's current branch — that reads
  # as a plausible but wrong branch name for what is really a missing or
  # corrupted clone.
  local ws_dir="${OUTER_REPO}/workspaces/sushigo-a"
  # sushigo-a intentionally has no .git of its own — see setup().

  run workspace_branch "${ws_dir}"
  [ "$status" -eq 0 ]
  [ "$output" = "?" ]
  [ "$output" != "lab-main" ]
}

@test "workspace_branch returns ? for a directory that does not exist" {
  run workspace_branch "${OUTER_REPO}/workspaces/does-not-exist"
  [ "$status" -eq 0 ]
  [ "$output" = "?" ]
}

# --- classify_process_table -------------------------------------------------

@test "classify_process_table reports running when every process is running" {
  table=$'PROCESS   PID       STATUS\nweb       111       running\nvite      112       running'

  run classify_process_table "$table"
  [ "$status" -eq 0 ]
  [ "$output" = "running|web:running vite:running" ]
}

@test "classify_process_table reports degraded when only some processes are running" {
  table=$'PROCESS   PID       STATUS\nweb       111       running\nvite      0         dead'

  run classify_process_table "$table"
  [ "$status" -eq 0 ]
  [ "$output" = "degraded|web:running vite:dead" ]
}

@test "classify_process_table reports stopped when no process is running" {
  table=$'PROCESS   PID       STATUS\nweb       0         dead\nvite      0         dead'

  run classify_process_table "$table"
  [ "$status" -eq 0 ]
  [ "$output" = "stopped|web:dead vite:dead" ]
}

@test "classify_process_table reports stale-socket for a table with no process rows" {
  table=$'PROCESS   PID       STATUS'

  run classify_process_table "$table"
  [ "$status" -eq 0 ]
  [ "$output" = "stale-socket|no processes reported" ]
}

@test "classify_process_table handles a single-process table" {
  table=$'PROCESS   PID       STATUS\nweb       111       running'

  run classify_process_table "$table"
  [ "$status" -eq 0 ]
  [ "$output" = "running|web:running" ]
}
