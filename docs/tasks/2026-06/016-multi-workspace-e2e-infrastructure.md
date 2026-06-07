# 016 - Multi-Workspace E2E Infrastructure — Docker Backend with Volume Mount + Local Cypress

**Type:** ✨ Feature  
**Priority:** High  
**GitHub Issue:** [#16](https://github.com/pakodiazdev/sushigo-dev-lab/issues/16)  
**Related:** [pakodiazdev/sushigo #166](https://github.com/pakodiazdev/sushigo/issues/166) — Cypress devlab config

---

## 📖 Story

**English:**  
As a developer using the dev-lab with multiple agents working in parallel, I need each workspace to have its own isolated E2E environment so I can run Cypress against my uncommitted changes without disrupting other agents or my own development data.

**Español:**  
Como desarrollador usando el dev-lab con múltiples agentes en paralelo, necesito que cada workspace tenga su propio entorno E2E aislado para poder correr Cypress contra mis cambios sin commitear sin afectar otros agentes ni mi propia data de desarrollo.

---

## 🧩 Context

The dev-lab supports up to 8 independent workspaces (sushigo-a through sushigo-h) for parallel development. The current E2E setup (`devtest_container` + VNC + Cypress in Docker) does not scale to this model:

- Cannot see uncommitted code changes (no volume mount)
- Single shared environment — only one E2E run at a time across all agents
- Heavy stack: nginx + php-fpm + Node + Vite + Cypress + VNC/X11
- Cypress runs headless in VNC — no real browser debugging

### Architecture

```
Shared Docker (existing, unchanged):
  PostgreSQL, Redis, Mailpit

Per-slot E2E Docker (new, lightweight):
  e2e-api-a → php:8.3 container
              volume: workspaces/sushigo-a/code/api
              port: 8901
              DB: sushigo_ws_a_e2e

Per-slot Local (no Docker):
  Vite E2E-a → VITE_API_URL=:8901, port 5181  (sees uncommitted changes)

Per-slot Cypress (local, real browser):
  make e2e WORKSPACE=sushigo-a → baseUrl: http://localhost:5181
```

### Port scheme

| Slot | Dev API | Dev Vite | E2E API | E2E Vite | E2E DB |
|---|---|---|---|---|---|
| sushigo-a | 8001 | 5171 | 8901 | 5181 | sushigo_ws_a_e2e |
| sushigo-b | 8002 | 5172 | 8902 | 5182 | sushigo_ws_b_e2e |
| sushigo-c | 8003 | 5173 | 8903 | 5183 | sushigo_ws_c_e2e |
| sushigo-d | 8004 | 5174 | 8904 | 5184 | sushigo_ws_d_e2e |
| sushigo-e | 8005 | 5175 | 8905 | 5185 | sushigo_ws_e_e2e |
| sushigo-f | 8006 | 5176 | 8906 | 5186 | sushigo_ws_f_e2e |
| sushigo-g | 8007 | 5177 | 8907 | 5187 | sushigo_ws_g_e2e |
| sushigo-h | 8008 | 5178 | 8908 | 5188 | sushigo_ws_h_e2e |

---

## ✅ Technical Tasks

### docker/php-e2e/Dockerfile

- [ ] ✨ Base image: `php:8.3-cli`
- [ ] ✨ Install Laravel required extensions: `pdo`, `pdo_pgsql`, `mbstring`, `bcmath`, `xml`, `tokenizer`, `ctype`, `curl`, `fileinfo`, `openssl`
- [ ] ✨ Install `composer` (for autoload)
- [ ] ✨ `WORKDIR /app`, `CMD ["php", "-S", "0.0.0.0:8099", "-t", "/app/public"]`

### docker-compose.e2e.yml

- [ ] ✨ Define 8 services `e2e-api-a` through `e2e-api-h`
- [ ] ✨ Each service: `build: docker/php-e2e`, volume mount, unique host port (`E2E_API_PORT_<LETTER>`), env vars (`APP_ENV=testing`, `DB_DATABASE=sushigo_ws_<letter>_e2e`, `CACHE_PREFIX=e2e_<letter>_`, `QUEUE_CONNECTION=sync`, DB connection vars)
- [ ] ✨ All services depend on `db` (shared PostgreSQL from docker-compose.yml)
- [ ] ✨ Use `network_mode: host` or shared network to reach the existing `db` container

### tools.env.example

- [ ] ✨ Add `E2E_API_PORT_A=8901` through `E2E_API_PORT_H=8908`
- [ ] ✨ Add `E2E_VITE_PORT_A=5181` through `E2E_VITE_PORT_H=5188`

### scripts/start-e2e.sh

- [ ] ✨ Accept `--workspace=sushigo-a` (or shorthand `a`)
- [ ] ✨ Validate workspace exists and has `.env`
- [ ] ✨ Load workspace `.env` to get `WORKSPACE_ROOT`
- [ ] ✨ Load `tools.env` to get `E2E_API_PORT_<LETTER>` and `E2E_VITE_PORT_<LETTER>`
- [ ] ✨ Start `e2e-api-<letter>` container via `docker compose -f docker-compose.e2e.yml up e2e-api-<letter> -d`
- [ ] ✨ Wait for the container to be ready (health check or retry loop)
- [ ] ✨ Create `sushigo_ws_<letter>_e2e` database if it does not exist
- [ ] ✨ Run `docker exec e2e-api-<letter> php artisan migrate --force`
- [ ] ✨ Run `docker exec e2e-api-<letter> php artisan db:seed --force`
- [ ] ✨ Launch Vite E2E server in background: `VITE_API_URL=http://localhost:${E2E_API_PORT} npm --prefix ${WORKSPACE_ROOT}/code/webapp run dev -- --port ${E2E_VITE_PORT} --host 0.0.0.0`
- [ ] ✨ Store Vite PID for cleanup by `stop-e2e.sh`
- [ ] ✨ Print summary: container port, Vite port, Cypress command to run
- [ ] ✅ `shellcheck scripts/start-e2e.sh` passes

### scripts/stop-e2e.sh

- [ ] ✨ Accept `--workspace=sushigo-a` (or shorthand `a`)
- [ ] ✨ Kill Vite E2E process (from stored PID)
- [ ] ✨ Stop `e2e-api-<letter>` container: `docker compose -f docker-compose.e2e.yml stop e2e-api-<letter>`
- [ ] ✅ `shellcheck scripts/stop-e2e.sh` passes

### Makefile

- [ ] ✨ Add `e2e` target: requires `WORKSPACE`, calls `scripts/start-e2e.sh`
- [ ] ✨ Add `e2e-stop` target: requires `WORKSPACE`, calls `scripts/stop-e2e.sh`
- [ ] ✨ Add both targets to `make help` output
- [ ] ✨ Add both to `.PHONY`

### sushigo repo (issue #166)

- [ ] ✨ `code/webapp/cypress.config.devlab.ts` — `baseUrl` from `VITE_PORT` env, artisan tasks via `docker exec e2e-api-<letter>`, Mailpit at `localhost:8025`
- [ ] ✨ `code/webapp/package.json` — add `cypress:open:devlab` and `cypress:run:devlab` scripts

---

## 🎯 Acceptance Criteria

- [ ] `make e2e WORKSPACE=sushigo-a` starts the full E2E stack for slot a and prints the Cypress command to run
- [ ] `make e2e WORKSPACE=sushigo-b` runs simultaneously and independently from sushigo-a
- [ ] Uncommitted changes in `workspaces/sushigo-a/code/api` are immediately visible to `e2e-api-a` (no rebuild)
- [ ] Uncommitted changes in `workspaces/sushigo-a/code/webapp` are immediately visible via Vite E2E
- [ ] `cy.task('db:reset')` runs artisan inside the E2E container, not against the dev DB
- [ ] `make e2e-stop WORKSPACE=sushigo-a` cleanly stops Vite E2E and the container
- [ ] Dev workspace continues running normally while E2E runs in parallel
- [ ] `shellcheck` passes on all new scripts
- [ ] `tools.env.example` documents all E2E port variables

---

## 🔗 References

- GitHub Issue: [pakodiazdev/sushigo-dev-lab #16](https://github.com/pakodiazdev/sushigo-dev-lab/issues/16)
- Cypress config (sushigo): [pakodiazdev/sushigo #166](https://github.com/pakodiazdev/sushigo/issues/166)
- Dev-lab port scheme: `tools.env.example`, `docs/architecture.md`

---

## ⏱️ Estimates

- **Optimistic:** `4h`
- **Pessimistic:** `8h`
- **Status:** 🔲 Backlog
