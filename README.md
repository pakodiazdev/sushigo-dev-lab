# sushigo-dev-lab

> **Multi-agent local development environment for [SushiGo](https://github.com/pakodiazdev/sushigo)**  
> Run multiple independent branches simultaneously — shared infrastructure, minimal thermal footprint.

---

## The problem

Working with AI coding agents (Claude Code, Copilot, Codex) naturally leads to parallel development: one agent builds a feature on branch A, another fixes a bug on branch B, you review and test both. The bottleneck isn't the AI — it's the machine.

The [SushiGo](https://github.com/pakodiazdev/sushigo) production dev stack is thorough and correct:

```
Current sushigo stack (with E2E running):

dev_container      Apache + PHP-FPM + Node + Vite watchers    ← branch you're developing
devtest_container  Apache + PHP-FPM + Node + Vite watchers    ← isolated test env
nginx_proxy        Nginx reverse proxy + SSL termination
postgres_container PostgreSQL 15
pgadmin_container  PgAdmin4 web UI
mailhog_container  Mailhog SMTP catcher
test_e2e           Apache + PHP-FPM + Node + Vite watchers    ← E2E isolated env
cypress            Chrome + Cypress runner (containerized)
cypress-ui         VNC server + X11 + Chrome + Cypress UI

= 9 containers
= 3 full PHP+Apache+Node stacks running simultaneously
= 1 browser inside Docker (VNC)
= Mac Intel fan at 100%, second branch impossible
```

This is the right architecture for a production-grade project. But on Mac Intel hardware, running the full stack while Cypress executes E2E tests causes sustained thermal throttling — the machine heats up, slows down, and makes it impossible to have a second agent working on a different branch at the same time.

The goal was not to replace the full stack — it's the reference. The goal was to find a **lighter alternative** for day-to-day multi-agent development that preserves independence between branches and doesn't require sacrificing thermal headroom.

```
sushigo-dev-lab approach:

Shared (Docker, 1 instance each):        Per workspace (local processes, lightweight):
  PostgreSQL  ──┬                          sushigo-a:  php artisan serve + npm run dev
  Redis       ──┼── one stack total        sushigo-b:  php artisan serve + npm run dev
  Mailpit     ──┘                          sushigo-c:  php artisan serve + npm run dev

No Nginx. No Apache. No browser in Docker. No VNC.
Cypress runs locally against whichever workspace is under test.
```

The result: multiple active branches, each with full API + frontend + isolated database, without the machine overheating.

---

## How it works

```
sushigo-dev-lab/
│
├── docker-compose.yml        # One PostgreSQL, one Redis, one Mailpit
│
└── scripts/
    ├── setup.sh              # Clone N workspaces, configure, install, migrate
    ├── init.sh               # Start one or all workspaces
    ├── create-workspace.sh   # Add a new workspace at any time
    ├── status.sh             # Show every workspace slot's branch, ports and runtime state
    └── reset-workspace-db.sh # Wipe + re-seed one workspace's database
```

Each workspace is a full clone of SushiGo with its own:

| | sushigo-a | sushigo-b | sushigo-c |
|---|---|---|---|
| Git branch | any | any | any |
| Laravel port | 8001 | 8002 | 8003 |
| Vite port | 5171 | 5172 | 5173 |
| Database | `sushigo_ws_a` | `sushigo_ws_b` | `sushigo_ws_c` |

**The key principle:** SushiGo knows how to boot itself (`init-agent-workspace.sh` + `Procfile.dev` live in the SushiGo repo). This lab only orchestrates — it never hardcodes framework internals.

```
scripts/init.sh
  └── workspaces/sushigo-a/init-agent-workspace.sh   ← self-contained boot
  └── workspaces/sushigo-b/init-agent-workspace.sh
  └── workspaces/sushigo-c/init-agent-workspace.sh
        └── overmind start -f Procfile.dev
              ├── web:    php artisan serve --port=$APP_PORT
              └── vite:   npm run dev -- --port $VITE_PORT
```

Process management uses **[Overmind](https://github.com/DarthSim/overmind)** — a Procfile supervisor that gives you colored logs, clean shutdown with Ctrl+C, and per-process restart (`overmind restart web`) without touching other workspaces.

---

## Prerequisites

| Tool | Min version | Install |
|---|---|---|
| Docker Desktop | any | [docker.com](https://www.docker.com/products/docker-desktop) |
| PHP | 8.2+ | `brew install php` |
| Composer | 2.x | `brew install composer` |
| Node | 20+ | `brew install node` |
| Overmind | any | `brew install overmind` |
| psql client | any | `brew install libpq && brew link libpq --force` |

> **Mac Intel note:** This setup was specifically designed to be lightweight on Mac Intel hardware. All heavy services (database, cache, mail) share a single Docker instance.

---

## Design philosophy

The [SushiGo](https://github.com/pakodiazdev/sushigo) full stack was designed with a clear goal: `docker compose up` → complete environment ready in minutes → developer adds value immediately, without fighting forgotten configurations. No manual steps, no environment drift, no "it works on my machine."

**sushigo-dev-lab inherits that same philosophy.** One command initializes everything: clones the repo, generates `.env` files, creates isolated databases, installs all dependencies, and runs migrations. The developer goes from zero to two (or three) independent, running environments without touching a config file.

```bash
# That's it. Two fully configured, isolated environments in one command.
./scripts/setup.sh --workspaces=2
```

This repo is a **complement**, not a replacement. The full sushigo stack remains the reference for CI, production-like testing, and team onboarding. The dev-lab is the lightweight alternative for day-to-day parallel development on Mac Intel hardware.

---

## Quickstart

```bash
# 1. Clone this repo
git clone https://github.com/pakodiazdev/sushigo-dev-lab.git
cd sushigo-dev-lab

# 2. Initialize 2 independent workspaces (shares Docker services, clones, configures, installs, migrates)
./scripts/setup.sh --workspaces=2

# 3. Start a workspace
./scripts/init.sh sushigo-a

# 4. Open in browser
open http://localhost:5171   # sushigo-a frontend
open http://localhost:8001   # sushigo-a API
```

After `setup.sh` you'll see:

```
✅ Setup complete — 3 workspaces ready

Workspace     Backend                    Frontend                   Database
sushigo-a     http://127.0.0.1:8001      http://localhost:5171       sushigo_ws_a
sushigo-b     http://127.0.0.1:8002      http://localhost:5172       sushigo_ws_b
sushigo-c     http://127.0.0.1:8003      http://localhost:5173       sushigo_ws_c

Next steps:
  Start all workspaces:      ./scripts/init.sh
  Start one workspace:       ./scripts/init.sh sushigo-a
  Add another workspace:     ./scripts/create-workspace.sh
  Reset workspace database:  ./scripts/reset-workspace-db.sh sushigo-a
```

---

## Scripts

### `setup.sh` — full initialization

```bash
./scripts/setup.sh --workspaces=3
./scripts/setup.sh --workspaces=2 --repo=git@github.com:pakodiazdev/sushigo.git
./scripts/setup.sh --workspaces=2 --branch=feature/065-my-feature
```

Clones SushiGo N times on `main` by default (or `--branch` if specified), generates isolated `.env` files, creates one PostgreSQL database per workspace, runs `composer install`, `npm install`, and `php artisan migrate --seed` for each. Idempotent — safe to re-run.

---

### `init.sh` — start workspaces

```bash
./scripts/init.sh               # start all workspaces (each in a background Overmind session)
./scripts/init.sh sushigo-a    # start one workspace (foreground, Overmind output)
```

Single-workspace mode runs in the foreground — Overmind shows colored logs for each process. Ctrl+C cleanly stops both Laravel and Vite. All-workspaces mode starts each workspace in the background; use `overmind connect web` inside the workspace directory to inspect logs.

---

### `create-workspace.sh` — add a workspace

```bash
./scripts/create-workspace.sh
./scripts/create-workspace.sh --branch=feature/066-other-feature
```

Auto-detects the next available letter and port. Clones sushigo on `main` by default, or on the specified branch. Creates the database and `.env` without touching existing workspaces.

---

### `status.sh` — workspace runtime overview

```bash
./scripts/status.sh
# or: make status
```

Reports every slot (`a` through `h`): git branch, `APP_PORT`, `VITE_PORT`, and a state derived
from actually talking to Overmind — not from the mere existence of `.overmind.sock`, which
survives both a clean `overmind quit` and an unclean crash of the Overmind master process.

| State | Meaning |
|---|---|
| `unconfigured` | no workspace directory / `.env` for this slot |
| `stopped` | no processes running (never started, or cleanly quit) |
| `running` | every process in the workspace's Procfile is running |
| `degraded` | some, but not all, processes are running |
| `stale-socket` | `.overmind.sock` exists but nothing answers on it |

---

### `reset-workspace-db.sh` — reset one database

```bash
./scripts/reset-workspace-db.sh sushigo-b
```

Drops `sushigo_ws_b`, recreates it, and runs `migrate --seed`. Other workspaces are untouched and keep running.

---

### Makefile shortcuts

```bash
make up                              # docker compose up -d
make down                            # docker compose down
make init                            # ./scripts/init.sh
make init WORKSPACE=sushigo-a        # ./scripts/init.sh sushigo-a
make status                          # ./scripts/status.sh
make reset-db WORKSPACE=sushigo-a    # ./scripts/reset-workspace-db.sh sushigo-a
make update-workspaces                # ./scripts/update-workspaces.sh
make logs                            # docker compose logs -f
```

---

## Day-to-day workflow

**Switch branch in a workspace:**
```bash
cd workspaces/sushigo-b
git fetch origin
git checkout feature/065-new-feature
```

**Restart only Laravel (without stopping Vite):**
```bash
# Inside the workspace's Overmind session:
overmind restart web
```

**Check Overmind process status inside a workspace:**
```bash
cd workspaces/sushigo-a
overmind status
```

**Stop all processes for one workspace:**
```bash
cd workspaces/sushigo-a
overmind stop
```

**Run Cypress against a specific workspace:**
```bash
cd workspaces/sushigo-a
CYPRESS_BASE_URL=http://localhost:5171 npx cypress open
```

---

## Shared services

| Service | URL | Purpose |
|---|---|---|
| PostgreSQL | `localhost:5432` | Database for all workspaces |
| Redis | `localhost:6379` | Cache / queues |
| Mailpit | http://localhost:8025 | Email UI (catches all outbound mail) |
| pgAdmin (opt-in) | http://localhost:5050 | Visual browser for the shared PostgreSQL instance |

All workspaces connect to the same PostgreSQL instance but use isolated databases (`sushigo_ws_a`, `sushigo_ws_b`, ...). Redis is shared — cache keys are namespaced per workspace via `CACHE_PREFIX` in each `.env`.

### pgAdmin

Not started by `docker compose up` / `make up` — pgAdmin only runs when you ask for it, so it never adds to the lab's default footprint:

```bash
make pgadmin         # start pgAdmin at http://127.0.0.1:5050
make pgadmin-stop     # stop pgAdmin only — db/redis/mailpit and every workspace keep running
```

Opening `http://127.0.0.1:5050` goes straight to the browser tree — no login. The shared PostgreSQL server is already registered and connects without a password prompt, so every `sushigo_ws_<letter>` (plus its `_test` and `_e2e` siblings) is visible immediately under **Servers → sushigo-dev-lab → Databases**.

Both the server definition and its credentials are generated at container startup from the same `POSTGRES_USER`/`POSTGRES_PASSWORD` the `db` service uses (see `.env.example`) — nothing is hardcoded, and nothing needs to be re-typed after changing them: recreate the container (`make pgadmin`, or `docker compose --profile tools up -d pgadmin --force-recreate`) and both the server entry and its stored password refresh automatically. pgAdmin's own preferences and connection history persist across restarts in the `pgadmin-data` volume. It binds to `127.0.0.1` only — override the port with `PGADMIN_HOST_PORT` in `.env` if `5050` is taken.

---

## Project context

**sushigo-dev-lab** is part of the [SushiGo](https://github.com/pakodiazdev/sushigo) ecosystem — a full-stack tenant platform built with:

- **Backend:** Laravel 12 · Passport OAuth · Spatie Permissions · PostgreSQL
- **Frontend:** React 19 · TanStack Router/Query · Zustand · Tailwind CSS
- **Mobile:** Flutter (in progress)

### Why this exists

The development workflow on SushiGo is AI-assisted: Claude Code, Copilot, and Codex agents work on different issues in parallel while the developer reviews, tests, and merges. This multiplies throughput significantly — but it requires multiple independent environments running at the same time.

The full sushigo Docker stack (`docker compose up`) is the correct approach for a single developer environment: reproducible, self-contained, zero manual configuration. The problem is hardware: running 9 containers (including 3 PHP+Apache+Node stacks and a Cypress browser) on Mac Intel causes thermal throttling that makes parallel work impossible.

This lab solves that by keeping the "one command → fully working environment" promise while drastically reducing the per-agent resource cost. The full stack stays as the reference for CI and production-like testing.

---

## Documentation

- [Architecture decisions](docs/architecture.md) — why shared services, why Overmind, port strategy
- [Working with agents](docs/agents.md) — branches, Overmind commands, database resets
- [Troubleshooting](docs/troubleshooting.md) — port conflicts, DB errors, PHP version issues, Vite CORS
- [Technical decisions (ADRs)](docs/decisions/index.md) — decision log with context, alternatives, and requirements

---

## License

This project is licensed under the [PolyForm Noncommercial License 1.0.0](LICENSE).

**You may:** use, study, and share this project for personal, educational, and portfolio purposes.  
**You may not:** use this project, or any derivative of it, for commercial purposes without explicit written permission from the author.

© 2026 [Pako Díaz](https://github.com/pakodiazdev). All commercial rights reserved.
