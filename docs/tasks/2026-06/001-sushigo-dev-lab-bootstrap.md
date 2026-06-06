# 001 - SushiGo Dev Lab — Bootstrap

**Type:** 🔧 Infrastructure / Developer Experience  
**Priority:** High  
**GitHub Issue:** [#1](https://github.com/pakodiazdev/sushigo-dev-lab/issues/1)  
**Related repo:** [pakodiazdev/sushigo](https://github.com/pakodiazdev/sushigo) — adds `Procfile.dev` + `init-agent-workspace.sh`

---

## 📖 Story

**English:**  
As a developer working on multiple SushiGo issues simultaneously, I need a local multi-agent environment that lets me run several independent clones of the project at the same time — each with its own branch, database, and ports — without overheating the machine.

**Español:**  
Como desarrollador trabajando en múltiples issues de SushiGo al mismo tiempo, necesito un entorno local multi-agente que me permita correr varios clones independientes del proyecto — cada uno con su propia rama, base de datos y puertos — sin sobrecalentar la máquina.

---

## 🧩 Context

The SushiGo full Docker stack is the correct and professional setup: `docker compose up` → everything ready in minutes → developer adds value immediately. However, when running E2E tests, the stack grows to:

```
dev_container      Apache + PHP-FPM + Node + Vite watchers
devtest_container  Apache + PHP-FPM + Node + Vite watchers
nginx_proxy        Nginx reverse proxy + SSL termination
postgres_container PostgreSQL 15
pgadmin_container  PgAdmin4 web UI
mailhog_container  Mailhog SMTP catcher
test_e2e           Apache + PHP-FPM + Node + Vite watchers
cypress            Chrome + Cypress runner (containerized)
cypress-ui         VNC server + X11 + Chrome + Cypress UI
```

9 containers, 3 full PHP+Apache+Node stacks, a browser inside Docker. On Mac Intel this causes sustained thermal throttling, making it impossible to work on a second branch simultaneously.

**This repo is a complement, not a replacement.** The full stack remains the reference for CI and production-like testing. The dev-lab provides the lightweight alternative for day-to-day multi-agent parallel development.

---

## 🏗️ Architecture

```
Docker (shared, 1 instance each):       Local per agent (Overmind):
  PostgreSQL  ──┐                          agent-a:  web (php artisan serve)
  Redis       ──┼──────────────────────    agent-b:  web (php artisan serve)
  Mailpit     ──┘                          agent-c:  vite (npm run dev)

No Nginx. No Apache container. No browser in Docker.
```

**Key principle:** SushiGo knows how to boot itself (`init-agent-workspace.sh` + `Procfile.dev` live in the sushigo repo). This lab only orchestrates — it never hardcodes Laravel or Vite internals.

### Port assignment

| Agent    | APP_PORT | VITE_PORT | DB database      |
|----------|----------|-----------|------------------|
| agent-a  | 8001     | 5171      | sushigo_agent_a  |
| agent-b  | 8002     | 5172      | sushigo_agent_b  |
| agent-c  | 8003     | 5173      | sushigo_agent_c  |

---

## ✅ Technical Tasks

### Phase 1 — sushigo repo changes

- [x] 📝 Add `Procfile.dev` at root of `sushigo` repo
- [x] 📝 Add `init-agent-workspace.sh` at root of `sushigo` repo (chmod +x)
- [x] 📝 Update `sushigo/CLAUDE.md` — document `init-agent-workspace.sh` as startup method when using dev-lab
- [x] 🧪 Verify: `./init-agent-workspace.sh` starts both services from a plain sushigo clone

### Phase 2 — dev-lab repo structure

- [x] 📝 `docker-compose.yml` — PostgreSQL 16, Redis 7-alpine, Mailpit
- [x] 📝 `.gitignore` — exclude `agents/` entirely
- [x] 📝 `Makefile` — shortcuts: `make up`, `make init`, `make reset-db AGENT=agent-a`
- [x] 📝 `doc/tasks/` structure — backlog + monthly folders (same as sushigo)

### Phase 3 — `scripts/setup.sh`

```
Usage: ./scripts/setup.sh --agents=3 [--repo=URL]
```

- [x] 🔧 Check prerequisites: `git`, `php` (≥8.2), `composer`, `node`, `npm`, `overmind`, `docker`, `psql`
- [x] 🔧 Start shared Docker services (`docker compose up -d`)
- [x] 🔧 Wait for PostgreSQL health check (max 30s)
- [x] 🔧 For each agent: clone sushigo on `main` (or `--branch` if specified) → `.env` → create DB → `composer install` → `npm install` → `key:generate` → `migrate --seed`
- [x] 🔧 Print summary table (agent / backend URL / frontend URL / DB)

### Phase 4 — `scripts/create-workspace.sh` _(renamed from `create-agent.sh`)_

- [x] 🔧 Auto-detect next available letter and port
- [x] 🔧 Clone sushigo on `main` by default; accept optional `--branch=<name>` argument to clone on a specific branch
- [x] 🔧 Configure `.env`, create DB, install deps, migrate

### Phase 5 — `scripts/init.sh`

```
Usage:
  ./scripts/init.sh             → start all agents (background Overmind sessions)
  ./scripts/init.sh agent-a     → start one agent (foreground)
```

- [x] 🔧 Single agent: `cd agents/sushigo-agent-<name> && ./init-agent-workspace.sh` (foreground)
- [x] 🔧 All agents: start each as a background Overmind session
- [x] 🔧 Verify Docker shared services are running before starting agents

### Phase 6 — `scripts/reset-workspace-db.sh` _(renamed from `reset-agent-db.sh`)_

```
Usage: ./scripts/reset-workspace-db.sh sushigo-a
```

- [x] 🔧 Drop → recreate → `migrate --seed` for one agent's DB only

### Phase 7 — Documentation

- [x] 📝 `README.md` — overview, real problem context, design philosophy, quickstart, scripts reference
- [x] 📝 `docs/architecture.md` — shared-services/local-execution rationale, Overmind decision, port table
- [x] 📝 `docs/workspaces.md` _(renamed from `agents.md`)_ — create workspaces, switch branches, Overmind commands
- [x] 📝 `docs/troubleshooting.md` — port conflicts, PostgreSQL not ready, overmind not found, PHP version mismatch, Vite CORS

---

## 🎯 Acceptance Criteria

- [x] `./scripts/setup.sh --workspaces=2` runs end-to-end without manual intervention
- [x] Each workspace starts with `./scripts/init.sh sushigo-a` and both backend + frontend respond
- [x] Workspaces are fully independent — switching branch in `sushigo-a` does not affect `sushigo-b`
- [x] `./scripts/reset-workspace-db.sh sushigo-b` wipes and re-seeds only `sushigo_b`
- [x] A single PostgreSQL, Redis, and Mailpit instance serves all workspaces
- [x] `./init-agent-workspace.sh` in sushigo root works standalone (without dev-lab)
- [x] Overmind stops both services cleanly with Ctrl+C
- [x] `docs/troubleshooting.md` covers at least 5 real error scenarios with solutions (20 sections)
- [x] README quickstart verified on a clean machine

---

## 🔗 References

- Overmind: https://github.com/DarthSim/overmind
- Procfile spec: https://devcenter.heroku.com/articles/procfile
- Prerequisites: PHP 8.2+ via Homebrew, Overmind (`brew install overmind`), Docker Desktop
- Related: [pakodiazdev/sushigo #144](https://github.com/pakodiazdev/sushigo/issues/144) — task tracked in sushigo backlog

---

## ⏱️ Estimates

- **Optimistic:** `6h`
- **Pessimistic:** `10h`
- **Tracked:** `~8h`
- **Closed:** `2026-06-05`
- **Status:** ✅ Done — 100% complete
