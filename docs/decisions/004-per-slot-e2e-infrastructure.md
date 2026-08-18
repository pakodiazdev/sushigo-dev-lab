# ADR-004: Per-slot lightweight E2E infrastructure, local Cypress over shared VNC/Docker Cypress

> **Status:** Accepted
> **Date:** 2026-06-07
> **Deciders:** pakodiazdev

---

## Context

The dev-lab supports up to 8 independent workspaces (`sushigo-a` through `sushigo-h`) so multiple agents can develop in parallel. The pre-existing E2E setup (`devtest_container` + VNC + Cypress running inside Docker) did not extend to that model: it had no volume mount, so it could not see a workspace's uncommitted changes; it was a single shared environment, so only one E2E run could happen at a time across all agents; and its stack (nginx + php-fpm + Node + Vite + Cypress + VNC/X11) was heavy for what amounted to running a Laravel API and a browser test runner.

E2E needed the same per-slot isolation philosophy as everything else in the lab — each workspace's E2E run needed its own backend, its own database, and its own ports, so agents could run Cypress simultaneously without interfering with each other or with their own dev data.

---

## Decision

Add one lightweight `e2e-api-<letter>` container per slot (`docker-compose.e2e.yml`, `docker/php-e2e/Dockerfile` — `php:8.3-cli` with the Laravel extensions, no nginx, no Node), each volume-mounting `workspaces/sushigo-<letter>/code/api` so uncommitted PHP changes are visible with no rebuild, and each backed by its own database `sushigo_ws_<letter>_e2e`. Each slot's frontend is a local (non-Docker) Vite dev server pointed at its slot's E2E API port, so uncommitted webapp changes are visible the same way. Cypress runs locally in a real browser against that slot's Vite URL — not headless inside a container. `make e2e WORKSPACE=sushigo-a` (`scripts/start-e2e.sh`) brings up the container, database, and Vite E2E server, then prints the separate `make cypress WORKSPACE=sushigo-a` / `make cypress-run WORKSPACE=sushigo-a` commands to open or run Cypress against it; `make e2e-stop WORKSPACE=sushigo-a` (`scripts/stop-e2e.sh`) tears the stack back down. Ports follow a fixed scheme (E2E API `8901`–`8908`, E2E Vite `5181`–`5188`) documented in `tools.env.example`.

> **Update (2026-07-14):** `docker/php-e2e/Dockerfile` was bumped from `php:8.3-cli` to `php:8.4-cli` in [#052](https://github.com/pakodiazdev/sushigo-dev-lab/issues/52) — the bind-mounted `vendor/` started resolving packages requiring PHP >= 8.4. The architecture described below is otherwise unchanged.

---

## Considered Options

### Option 1: Keep the shared VNC/Docker Cypress container (`devtest_container`)

The pre-existing setup: one shared container running nginx + php-fpm + Node + Vite + Cypress, viewed over VNC.

**Pros:**
- Already existed, no new infrastructure to build

**Cons:**
- No volume mount — could not see uncommitted code, so it could only test what was already committed and pushed into the image
- Single shared instance — only one agent could run E2E at a time, defeating the lab's whole parallel-workspace premise
- Heavy stack (nginx + php-fpm + Node + Vite + Cypress + VNC/X11) for what is fundamentally an API + a browser
- Cypress ran headless inside VNC — no real local browser for interactive debugging of a failing test

---

### Option 2: Per-slot lightweight Docker backend + local Vite + local Cypress ✅ *(chosen)*

Described in Decision above: one thin `php:8.3-cli` container per slot with a volume mount, one isolated `_e2e` database per slot, local Vite and local Cypress.

**Pros:**
- Volume mount means uncommitted changes in `code/api` are visible immediately, no rebuild
- Fully isolated per slot — database, ports, and container are all slot-scoped, so up to 8 agents can run E2E simultaneously without interference
- Much lighter than the previous stack — no nginx, no Node, no VNC/X11 in the container
- Cypress opens in a real local browser — normal interactive debugging works
- Expandable — future services can be added to `docker-compose.e2e.yml` without touching application code

**Cons:**
- Introduces a second, E2E-specific Docker Compose file (`docker-compose.e2e.yml`) alongside the shared `docker-compose.yml`, and a second `Dockerfile` (`docker/php-e2e/`) to maintain
- 8 pre-defined services (one per slot) started on demand, rather than a single dynamically-parameterized service — chosen for simplicity over Compose's more complex `--scale`/templating mechanisms
- Frontend E2E serving relies on a local (non-Docker) Vite process per slot rather than a fully containerized frontend, so the E2E environment is not 100% container-isolated from the host

---

### Option 3: Fully containerize both API and frontend per slot (Docker Compose profiles, no local Vite)

Run both the PHP backend and a Vite dev server inside Docker per slot, keeping the whole E2E stack containerized.

**Pros:**
- Full environment parity with production containerization
- No local Node process management needed

**Cons:**
- Frontend Docker containers watching a bind-mounted `node_modules` across 8 slots is slow and flaky in practice (cross-platform file-watching overhead) compared to running Vite natively on the host
- Doesn't materially improve isolation over Option 2's per-slot local Vite, since ports and working directories are already slot-scoped either way

---

## Consequences

**Positive:**
- `make e2e WORKSPACE=sushigo-a` and `make e2e WORKSPACE=sushigo-b` run fully independently and simultaneously — different containers, different databases, different ports
- Uncommitted changes in both `code/api` and `code/webapp` are immediately visible to E2E runs with no rebuild step
- Dev workspaces keep running normally while E2E runs in parallel — the E2E stack is fully separate from each slot's dev API/DB
- Cypress config changes (`cypress.config.devlab.ts`, `cypress:open:devlab`/`cypress:run:devlab` scripts) live in the `sushigo` repo itself, tracked separately under sushigo issue #166

**Negative / trade-offs:**
- Two Docker Compose files now exist in the repo (`docker-compose.yml` for shared services, `docker-compose.e2e.yml` for per-slot E2E) — a contributor must know which one governs a given service
- The port scheme (8901–8908 / 5181–5188) is a fixed table that must be extended manually if the lab ever grows past 8 slots

**Neutral:**
- The old `devtest_container` + VNC setup is fully superseded and removed by this change — there is no fallback path to the shared-container model

---

## Requirements Addressed

| ID | Description | Type |
|----|-------------|------|
| — | `make e2e WORKSPACE=sushigo-a` must start that slot's E2E API container, create its `_e2e` database, run migrations, launch its Vite E2E server, and print the `make cypress`/`make cypress-run` commands to run against it | Functional |
| — | Two slots must be able to run `make e2e` simultaneously without interfering with each other | Functional |
| — | Uncommitted changes in a workspace's `code/api` and `code/webapp` must be visible to its E2E run without a rebuild | Functional |
| — | `cy.task('db:reset')`/`cy.task('test:reset')` must run against the slot's E2E database, never its dev database | Functional |
| — | `make e2e-stop WORKSPACE=sushigo-a` must cleanly stop that slot's Vite E2E process and container | Functional |
| — | A running dev workspace must be unaffected by starting or stopping E2E for the same slot | Non-functional |
| — | `shellcheck scripts/start-e2e.sh scripts/stop-e2e.sh` must pass with no errors | Non-functional |

---

## Links

- Related issue: [#16 — Multi-workspace E2E infrastructure — Docker backend with volume mount + local Cypress](https://github.com/pakodiazdev/sushigo-dev-lab/issues/16)
- Related issue (sushigo, Cypress config): [pakodiazdev/sushigo#166](https://github.com/pakodiazdev/sushigo/issues/166)
- Implemented in PR: [#17](https://github.com/pakodiazdev/sushigo-dev-lab/pull/17)
- PHP version bump: [#52 — E2E container stuck on PHP 8.3, SONAR_TOKEN not refreshed on workspace re-setup](https://github.com/pakodiazdev/sushigo-dev-lab/issues/52)
- Related ADR: [ADR-003 — Safe workspace deletion ordering](003-safe-workspace-deletion.md) (deletes a workspace's E2E stack before dropping its `_e2e` database)
