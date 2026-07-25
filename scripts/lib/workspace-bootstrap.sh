#!/bin/bash
set -euo pipefail

# ---------------------------------------------------------------------------
# workspace-bootstrap.sh — Shared workspace bootstrap logic
#
# Sourced by setup.sh, create-workspace.sh, and init.sh. Each function
# receives the workspace directory and any config it needs as arguments —
# no global state — so a single edit here reaches every caller.
# ---------------------------------------------------------------------------

# Escape a value for use as a sed replacement string: backslash, ampersand,
# and the | delimiter are special in the replacement position.
sed_esc() { printf '%s' "$1" | sed 's/\\/\\\\/g' | sed 's/[&|]/\\&/g'; }

# configure_api_env <ws_dir> <letter> <app_port> <vite_port> <db_name> <pg_host> <pg_user> <pg_pass>
# Copies code/api/.env.example to code/api/.env and applies the standard
# per-workspace overrides (ports, DB connection, cache prefix, CORS, dev toggles).
configure_api_env() {
  local ws_dir="$1"
  local letter="$2"
  local app_port="$3"
  local vite_port="$4"
  local db_name="$5"
  local pg_host="$6"
  local pg_user="$7"
  local pg_pass="$8"
  local env_file="${ws_dir}/code/api/.env"

  cp "${ws_dir}/code/api/.env.example" "${env_file}"
  sed -i '' "s|^APP_URL=.*|APP_URL=http://127.0.0.1:${app_port}|" "${env_file}"
  sed -i '' "s|^DB_HOST=.*|DB_HOST=$(sed_esc "${pg_host}")|" "${env_file}"
  sed -i '' "s|^DB_DATABASE=.*|DB_DATABASE=$(sed_esc "${db_name}")|" "${env_file}"
  sed -i '' "s|^DB_USERNAME=.*|DB_USERNAME=$(sed_esc "${pg_user}")|" "${env_file}"
  sed -i '' "s|^DB_PASSWORD=.*|DB_PASSWORD=$(sed_esc "${pg_pass}")|" "${env_file}"

  # Unique cache/queue prefix to avoid Redis key collisions between workspaces
  if grep -q "^CACHE_PREFIX" "${env_file}"; then
    sed -i '' "s|^CACHE_PREFIX=.*|CACHE_PREFIX=ws_${letter}_|" "${env_file}"
  else
    echo "CACHE_PREFIX=ws_${letter}_" >> "${env_file}"
  fi

  # Local development toggles
  sed -i '' "s|^LOGIN_WITH_DEVDEBUG=.*|LOGIN_WITH_DEVDEBUG=true|" "${env_file}"
  sed -i '' "s|^DEV_LOGIN_ALLOWED_ENVIRONMENTS=.*|DEV_LOGIN_ALLOWED_ENVIRONMENTS=dev,devtest,local|" "${env_file}"
  sed -i '' "s|^CLOCK_SIMULATION_ENABLED=.*|CLOCK_SIMULATION_ENABLED=true|" "${env_file}"
  sed -i '' "s|^PAYROLL_SEED_ENABLED=.*|PAYROLL_SEED_ENABLED=true|" "${env_file}"

  # Allow the workspace's Vite dev-server port in CORS (both localhost and 127.0.0.1)
  local cors_origins="http://localhost:${vite_port},http://127.0.0.1:${vite_port}"
  if grep -q "^CORS_ALLOWED_ORIGINS" "${env_file}"; then
    sed -i '' "s|^CORS_ALLOWED_ORIGINS=.*|CORS_ALLOWED_ORIGINS=${cors_origins}|" "${env_file}"
  else
    echo "CORS_ALLOWED_ORIGINS=${cors_origins}" >> "${env_file}"
  fi

  # Point Swagger to this workspace's backend port so generated docs hit the right server
  if grep -q "^L5_SWAGGER_CONST_HOST" "${env_file}"; then
    sed -i '' "s|^L5_SWAGGER_CONST_HOST=.*|L5_SWAGGER_CONST_HOST=http://127.0.0.1:${app_port}|" "${env_file}"
  else
    echo "L5_SWAGGER_CONST_HOST=http://127.0.0.1:${app_port}" >> "${env_file}"
  fi
}

# configure_webapp_env <ws_dir> <app_port> <ws_label>
# Writes code/webapp/.env. VITE_HMR_HOST is intentionally unset — Vite
# auto-detects it in local dev.
configure_webapp_env() {
  local ws_dir="$1"
  local app_port="$2"
  local ws_label="$3"

  cat > "${ws_dir}/code/webapp/.env" <<EOF
VITE_API_URL=http://localhost:${app_port}/api/v1
VITE_APP_ENV=dev
VITE_TIME_FORMAT=12
VITE_DEV_DEBUGGER_START_HIDDEN=false
VITE_LOGIN_WITH_DEVDEBUG=true
VITE_DEV_LOGIN_ALLOWED_ENVIRONMENTS=dev,devtest
VITE_ENV_BADGE="🟢 "
VITE_AGENT_LABEL="${ws_label} "
VITE_WEEK_START_DAY=1
EOF
}

# configure_workspace_env <ws_dir> <app_port> <vite_port> <db_name> [sonar_token]
# Writes the workspace-root .env (read by init.sh) and propagates SONAR_TOKEN
# as SONAR_TOKEN_API / SONAR_TOKEN_WEBAPP — the keys the workspace's own
# tooling (e.g. /sonar-review) expects.
configure_workspace_env() {
  local ws_dir="$1"
  local app_port="$2"
  local vite_port="$3"
  local db_name="$4"
  local sonar_token="${5:-}"

  cat > "${ws_dir}/.env" <<EOF
APP_PORT=${app_port}
VITE_PORT=${vite_port}
DB_DATABASE=${db_name}
WORKSPACE_ROOT=${ws_dir}
EOF

  if [ -n "${sonar_token}" ]; then
    echo "SONAR_TOKEN_API=${sonar_token}" >> "${ws_dir}/.env"
    echo "SONAR_TOKEN_WEBAPP=${sonar_token}" >> "${ws_dir}/.env"
  fi
}

# write_procfile <ws_dir>
# Writes Procfile.dev with absolute paths so overmind works regardless of cwd
# (overmind creates its own tmux server which does not inherit the caller's cwd).
write_procfile() {
  local ws_dir="$1"
  cat > "${ws_dir}/Procfile.dev" <<'PROCFILE'
web:    php -S 0.0.0.0:${APP_PORT:-8000} -t ${WORKSPACE_ROOT}/code/api/public
vite:   npm --prefix ${WORKSPACE_ROOT}/code/webapp run dev -- --port ${VITE_PORT:-5173} --host 0.0.0.0
PROCFILE
}

# mark_procfile_skip_worktree <ws_dir>
# Marks Procfile.dev as skip-worktree: dev-lab owns it locally, git ignores changes.
# Safe no-op if the file isn't tracked yet.
mark_procfile_skip_worktree() {
  local ws_dir="$1"
  git -C "${ws_dir}" ls-files --error-unmatch Procfile.dev &>/dev/null 2>&1 && \
    git -C "${ws_dir}" update-index --skip-worktree Procfile.dev || true
}

# install_deps <ws_dir>
# Installs PHP and Node dependencies.
install_deps() {
  local ws_dir="$1"

  echo "  📚 Installing PHP dependencies..."
  (cd "${ws_dir}/code/api" && composer install --no-interaction --prefer-dist --no-progress --quiet)

  echo "  📦 Installing Node dependencies..."
  (cd "${ws_dir}/code/webapp" && npm install --silent)
}

# bootstrap_laravel <ws_dir> <db_name_test>
# One-time Laravel bootstrap for a freshly configured workspace: app key,
# isolated test env, Passport keys, migrations, seeders, and Swagger docs.
bootstrap_laravel() {
  local ws_dir="$1"
  local db_name_test="$2"
  local api_dir="${ws_dir}/code/api"

  echo "  🔑 Generating app key..."
  (cd "${api_dir}" && php artisan key:generate --ansi --quiet)

  # .env.testing gives this workspace its own test database. Laravel loads this
  # file INSTEAD OF .env when APP_ENV=testing (phpunit.xml sets that), so it must
  # carry a full copy of .env — not just the overridden key — plus phpunit.xml
  # already forces DB_HOST/PORT/USERNAME/PASSWORD, so only DB_DATABASE differs.
  echo "  🧪 Configuring .env.testing (isolated test database)..."
  cp "${api_dir}/.env" "${api_dir}/.env.testing"
  sed -i '' "s|^DB_DATABASE=.*|DB_DATABASE=$(sed_esc "${db_name_test}")|" "${api_dir}/.env.testing"

  echo "  🔐 Generating Passport OAuth keys..."
  (cd "${api_dir}" && php artisan passport:keys --force --quiet)

  echo "  🛠  Running migrations and seeders..."
  (cd "${api_dir}" && php artisan migrate --force --quiet)
  (cd "${api_dir}" && php artisan db:seed --force --quiet)

  echo "  📖 Generating Swagger docs..."
  (cd "${api_dir}" && php artisan l5-swagger:generate --quiet) || \
    echo "  ⚠️  Swagger doc generation failed — continuing without docs (see sushigo repo for the fix)"
}
