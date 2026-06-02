# Architecture

## Philosophy

```
Docker  = shared infrastructure  (PostgreSQL, Redis, Mailpit)
Local   = per-workspace execution (Laravel, Vite, Overmind)
```

Heavy services run once and are shared. Everything that must be isolated per branch (code, database, ports) runs locally as lightweight processes.

## Why this approach

The full [SushiGo](https://github.com/pakodiazdev/sushigo) Docker stack runs 9 containers when E2E tests are active — including 3 PHP+Apache+Node stacks and a Chromium browser in Docker. On Mac Intel hardware, running the full stack while Cypress executes causes sustained thermal throttling that makes working on a second branch simultaneously impossible.

This lab keeps the "one command → fully working environment" promise at a fraction of the resource cost.

## Component responsibilities

| Component | Where | Responsibility |
|---|---|---|
| `docker-compose.yml` | dev-lab | PostgreSQL, Redis, Mailpit — one instance, shared by all workspaces |
| `scripts/setup.sh` | dev-lab | Clone sushigo N times, configure, install, migrate |
| `scripts/init.sh` | dev-lab | Single workspace: delegates to `init-agent-workspace.sh` (foreground). All workspaces: sources `.env` + `overmind start -D` per workspace (background) |
| `scripts/create-workspace.sh` | dev-lab | Add a new workspace at any time |
| `scripts/reset-workspace-db.sh` | dev-lab | Wipe + remigrate one workspace's DB |
| `Procfile.dev` | sushigo | Define which processes to run (web + vite) |
| `init-agent-workspace.sh` | sushigo | Read `.env`, start Overmind |

**Key principle:** sushigo knows how to boot itself via `init-agent-workspace.sh` and `Procfile.dev`. The dev-lab handles cloning, environment configuration, and database setup — then delegates process management to sushigo's own boot script.

## Workspace isolation

Each workspace is a full git clone of sushigo with:

| Resource | Isolated per workspace |
|---|---|
| Git branch | ✅ independent |
| Laravel process | ✅ own `php -S` on unique port |
| Vite process | ✅ own `npm run dev` on unique port |
| PostgreSQL database | ✅ `sushigo_ws_<letter>` |
| `.env` file | ✅ own APP_PORT, VITE_PORT, DB_DATABASE |

Redis and Mailpit are shared — this is intentional. Cache keys are namespaced by `CACHE_PREFIX` set in each workspace's `code/api/.env` (the Laravel env, not the workspace root `.env`). Mailpit captures all outbound mail from all workspaces in one UI, which is convenient for development.

## Port assignment

| Workspace | APP_PORT | VITE_PORT | Database |
|---|---|---|---|
| sushigo-a | 8001 | 5171 | sushigo_ws_a |
| sushigo-b | 8002 | 5172 | sushigo_ws_b |
| sushigo-c | 8003 | 5173 | sushigo_ws_c |
| sushigo-d | 8004 | 5174 | sushigo_ws_d |

Ports are auto-assigned sequentially by `create-workspace.sh`. No manual configuration needed.

## Process management: Overmind

Each workspace's processes are managed by [Overmind](https://github.com/DarthSim/overmind), a Procfile supervisor written in Go.

```
Procfile.dev (in the sushigo repo)
  web:   php -S 0.0.0.0:$APP_PORT -t public
  vite:  npm run dev -- --port $VITE_PORT
```

Overmind gives:
- Colored, labeled logs for each process
- Clean shutdown with Ctrl+C (both processes stop together)
- Per-process restart: `overmind restart web`
- Process inspection: `overmind connect web`
- Background mode: `overmind start -f Procfile.dev -D`

## Startup flow

```
make init WORKSPACE=sushigo-a
  └── scripts/init.sh sushigo-a
        └── cd workspaces/sushigo-a
        └── bash init-agent-workspace.sh
              └── source .env  (APP_PORT=8001, VITE_PORT=5171)
              └── overmind start -f Procfile.dev
                    ├── web:   php -S 0.0.0.0:8001 -t public
                    └── vite:  npm run dev -- --port 5171
```
