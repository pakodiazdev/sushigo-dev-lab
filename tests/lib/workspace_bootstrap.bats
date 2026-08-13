#!/usr/bin/env bats
# ---------------------------------------------------------------------------
# workspace_bootstrap.bats — Coverage for the pure configuration helpers in
# scripts/lib/workspace-bootstrap.sh: sed_esc, configure_api_env,
# configure_webapp_env and configure_workspace_env.
#
# install_deps and bootstrap_laravel are intentionally out of scope — they
# shell out to composer/npm/php and are side-effect heavy, not config-only.
# ---------------------------------------------------------------------------

bats_require_minimum_version 1.5.0

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  FIXTURES_DIR="${REPO_ROOT}/tests/fixtures"

  # shellcheck source=../../scripts/lib/workspace-bootstrap.sh
  source "${REPO_ROOT}/scripts/lib/workspace-bootstrap.sh"

  WS_DIR="$(mktemp -d)"
  mkdir -p "${WS_DIR}/code/api" "${WS_DIR}/code/webapp"
  cp "${FIXTURES_DIR}/api.env.example" "${WS_DIR}/code/api/.env.example"
}

teardown() {
  rm -rf "${WS_DIR}"
}

# --- sed_esc -----------------------------------------------------------

@test "sed_esc leaves a plain string unchanged" {
  run sed_esc "simplevalue"
  [ "$status" -eq 0 ]
  [ "$output" = "simplevalue" ]
}

@test "sed_esc escapes a backslash" {
  run sed_esc 'a\b'
  [ "$status" -eq 0 ]
  [ "$output" = 'a\\b' ]
}

@test "sed_esc escapes an ampersand" {
  run sed_esc 'a&b'
  [ "$status" -eq 0 ]
  [ "$output" = 'a\&b' ]
}

@test "sed_esc escapes a pipe" {
  run sed_esc 'a|b'
  [ "$status" -eq 0 ]
  [ "$output" = 'a\|b' ]
}

@test "sed_esc escapes a mix of special characters in one value" {
  run sed_esc 'p\a|s&s'
  [ "$status" -eq 0 ]
  [ "$output" = 'p\\a\|s\&s' ]
}

@test "sed_esc handles an empty string" {
  run sed_esc ""
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}

# --- configure_api_env: value substitution ------------------------------

@test "configure_api_env writes .env from .env.example with the given values" {
  configure_api_env "${WS_DIR}" "a" "8001" "5171" "sushigo_ws_a" "127.0.0.1" "admin" "admin"

  [ -f "${WS_DIR}/code/api/.env" ]
  grep -qF "APP_URL=http://127.0.0.1:8001" "${WS_DIR}/code/api/.env"
  grep -qF "DB_HOST=127.0.0.1" "${WS_DIR}/code/api/.env"
  grep -qF "DB_DATABASE=sushigo_ws_a" "${WS_DIR}/code/api/.env"
  grep -qF "DB_USERNAME=admin" "${WS_DIR}/code/api/.env"
  grep -qF "DB_PASSWORD=admin" "${WS_DIR}/code/api/.env"
  grep -qF "LOGIN_WITH_DEVDEBUG=true" "${WS_DIR}/code/api/.env"
  grep -qF "DEV_LOGIN_ALLOWED_ENVIRONMENTS=dev,devtest,local" "${WS_DIR}/code/api/.env"
  grep -qF "CLOCK_SIMULATION_ENABLED=true" "${WS_DIR}/code/api/.env"
  grep -qF "PAYROLL_SEED_ENABLED=true" "${WS_DIR}/code/api/.env"
}

@test "configure_api_env preserves a DB password containing sed-special characters" {
  # &, | and \ are all significant to the `s|...|...|` command used internally
  # (| is the delimiter). sed_esc must neutralize them so the literal password
  # — not a mangled or partially-interpreted one — lands in the file.
  configure_api_env "${WS_DIR}" "a" "8001" "5171" "sushigo_ws_a" "127.0.0.1" "admin" 'p&ss|word\x'

  grep -qF 'DB_PASSWORD=p&ss|word\x' "${WS_DIR}/code/api/.env"
}

@test "configure_api_env does not leave the original .env.example untouched value in .env" {
  configure_api_env "${WS_DIR}" "a" "8001" "5171" "sushigo_ws_a" "127.0.0.1" "admin" "admin"

  run ! grep -qF "APP_URL=https://api.sushigo.local" "${WS_DIR}/code/api/.env"
}

# --- configure_api_env: missing-key append branch -----------------------

@test "configure_api_env appends CACHE_PREFIX when the key is absent (commented out)" {
  configure_api_env "${WS_DIR}" "b" "8002" "5172" "sushigo_ws_b" "127.0.0.1" "admin" "admin"

  [ "$(grep -c '^CACHE_PREFIX=ws_b_$' "${WS_DIR}/code/api/.env")" -eq 1 ]
}

@test "configure_api_env appends CORS_ALLOWED_ORIGINS when the key is absent" {
  configure_api_env "${WS_DIR}" "a" "8001" "5171" "sushigo_ws_a" "127.0.0.1" "admin" "admin"

  grep -qF "CORS_ALLOWED_ORIGINS=http://localhost:5171,http://127.0.0.1:5171" "${WS_DIR}/code/api/.env"
}

@test "configure_api_env appends L5_SWAGGER_CONST_HOST when the key is absent" {
  configure_api_env "${WS_DIR}" "a" "8001" "5171" "sushigo_ws_a" "127.0.0.1" "admin" "admin"

  grep -qF "L5_SWAGGER_CONST_HOST=http://127.0.0.1:8001" "${WS_DIR}/code/api/.env"
}

# --- configure_api_env: replacement branch when the key already exists --

@test "configure_api_env replaces an existing CACHE_PREFIX instead of duplicating it" {
  printf 'CACHE_PREFIX=stale_\n' >> "${WS_DIR}/code/api/.env.example"

  configure_api_env "${WS_DIR}" "c" "8003" "5173" "sushigo_ws_c" "127.0.0.1" "admin" "admin"

  [ "$(grep -c '^CACHE_PREFIX=' "${WS_DIR}/code/api/.env")" -eq 1 ]
  grep -qF "CACHE_PREFIX=ws_c_" "${WS_DIR}/code/api/.env"
}

@test "configure_api_env replaces an existing CORS_ALLOWED_ORIGINS instead of duplicating it" {
  printf 'CORS_ALLOWED_ORIGINS=http://stale\n' >> "${WS_DIR}/code/api/.env.example"

  configure_api_env "${WS_DIR}" "a" "8001" "5171" "sushigo_ws_a" "127.0.0.1" "admin" "admin"

  [ "$(grep -c '^CORS_ALLOWED_ORIGINS=' "${WS_DIR}/code/api/.env")" -eq 1 ]
  grep -qF "CORS_ALLOWED_ORIGINS=http://localhost:5171,http://127.0.0.1:5171" "${WS_DIR}/code/api/.env"
}

@test "configure_api_env replaces an existing L5_SWAGGER_CONST_HOST instead of duplicating it" {
  printf 'L5_SWAGGER_CONST_HOST=http://stale\n' >> "${WS_DIR}/code/api/.env.example"

  configure_api_env "${WS_DIR}" "a" "8001" "5171" "sushigo_ws_a" "127.0.0.1" "admin" "admin"

  [ "$(grep -c '^L5_SWAGGER_CONST_HOST=' "${WS_DIR}/code/api/.env")" -eq 1 ]
  grep -qF "L5_SWAGGER_CONST_HOST=http://127.0.0.1:8001" "${WS_DIR}/code/api/.env"
}

# --- configure_webapp_env -----------------------------------------------

@test "configure_webapp_env writes the expected webapp .env content" {
  configure_webapp_env "${WS_DIR}" "8001" "🅰️"

  [ -f "${WS_DIR}/code/webapp/.env" ]
  grep -qF "VITE_API_URL=http://localhost:8001/api/v1" "${WS_DIR}/code/webapp/.env"
  grep -qF "VITE_APP_ENV=dev" "${WS_DIR}/code/webapp/.env"
  grep -qF 'VITE_AGENT_LABEL="🅰️ "' "${WS_DIR}/code/webapp/.env"
  grep -qF "VITE_WEEK_START_DAY=1" "${WS_DIR}/code/webapp/.env"
  run ! grep -q "^VITE_HMR_HOST=" "${WS_DIR}/code/webapp/.env"
}

# --- configure_workspace_env ---------------------------------------------

@test "configure_workspace_env writes the workspace-root .env without a sonar token" {
  configure_workspace_env "${WS_DIR}" "8001" "5171" "sushigo_ws_a"

  [ -f "${WS_DIR}/.env" ]
  grep -qF "APP_PORT=8001" "${WS_DIR}/.env"
  grep -qF "VITE_PORT=5171" "${WS_DIR}/.env"
  grep -qF "DB_DATABASE=sushigo_ws_a" "${WS_DIR}/.env"
  grep -qF "WORKSPACE_ROOT=${WS_DIR}" "${WS_DIR}/.env"
  run ! grep -q "^SONAR_TOKEN_API=" "${WS_DIR}/.env"
  run ! grep -q "^SONAR_TOKEN_WEBAPP=" "${WS_DIR}/.env"
}

@test "configure_workspace_env propagates a sonar token to both expected keys" {
  configure_workspace_env "${WS_DIR}" "8001" "5171" "sushigo_ws_a" "sq_abc123"

  grep -qF "SONAR_TOKEN_API=sq_abc123" "${WS_DIR}/.env"
  grep -qF "SONAR_TOKEN_WEBAPP=sq_abc123" "${WS_DIR}/.env"
}
