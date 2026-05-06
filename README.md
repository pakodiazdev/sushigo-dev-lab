# sushigo-dev-lab

> **Multi-agent local development environment for [SushiGo](https://github.com/pakodiazdev/sushigo)**  
> Run multiple independent branches simultaneously — shared infrastructure, zero redundancy.

---

## The problem

Modern AI-assisted development means working on several issues at the same time: one agent fixing a bug, another building a feature, you reviewing both. The naive solution — spin up a full Docker stack per clone — kills a Mac in minutes.

```
❌ Naive approach                     ✅ This repo
─────────────────────────────         ──────────────────────────────────
agent-a: PostgreSQL + Redis           PostgreSQL  ──┐
agent-b: PostgreSQL + Redis           Redis       ──┼── shared (1 instance each)
agent-c: PostgreSQL + Redis           Mailpit     ──┘
= 3× everything, 100% waste           
                                      agent-a: Laravel + Vite (local)
                                      agent-b: Laravel + Vite (local)
                                      agent-c: Laravel + Vite (local)
                                      = 3× only what must be separate
```

---

## How it works

```
sushigo-dev-lab/
│
├── docker-compose.yml        # One PostgreSQL, one Redis, one Mailpit
│
└── scripts/
    ├── setup.sh              # Clone N agents, configure, install, migrate
    ├── init.sh               # Start one or all agents
    ├── create-agent.sh       # Add a new agent at any time
    └── reset-agent-db.sh     # Wipe + re-seed one agent's database
```

Each agent is a full clone of SushiGo with its own:

| | agent-a | agent-b | agent-c |
|---|---|---|---|
| Git branch | any | any | any |
| Laravel port | 8001 | 8002 | 8003 |
| Vite port | 5171 | 5172 | 5173 |
| Database | `sushigo_agent_a` | `sushigo_agent_b` | `sushigo_agent_c` |

**The key principle:** SushiGo knows how to boot itself (`init-agent-workspace.sh` + `Procfile.dev` live in the SushiGo repo). This lab only orchestrates — it never hardcodes framework internals.

```
scripts/init.sh
  └── agents/sushigo-agent-a/init-agent-workspace.sh   ← self-contained boot
  └── agents/sushigo-agent-b/init-agent-workspace.sh
  └── agents/sushigo-agent-c/init-agent-workspace.sh
        └── overmind start -f Procfile.dev
              ├── web:    php artisan serve --port=$APP_PORT
              └── vite:   npm run dev -- --port $VITE_PORT
```

Process management uses **[Overmind](https://github.com/DarthSim/overmind)** — a Procfile supervisor that gives you colored logs, clean shutdown with Ctrl+C, and per-process restart (`overmind restart web`) without touching other agents.

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

## Quickstart

```bash
# 1. Clone this repo
git clone https://github.com/pakodiazdev/sushigo-dev-lab.git
cd sushigo-dev-lab

# 2. Start shared services (PostgreSQL, Redis, Mailpit)
docker compose up -d

# 3. Initialize 3 independent agents (clone + configure + install + migrate)
./scripts/setup.sh --agents=3

# 4. Start a specific agent
./scripts/init.sh agent-a

# 5. Open in browser
open http://localhost:5171   # agent-a frontend
open http://localhost:8001   # agent-a API
```

After `setup.sh` you'll see:

```
✅ Setup complete — 3 agents ready

Agent     Backend                    Frontend                   Database
agent-a   http://127.0.0.1:8001      http://localhost:5171       sushigo_agent_a
agent-b   http://127.0.0.1:8002      http://localhost:5172       sushigo_agent_b
agent-c   http://127.0.0.1:8003      http://localhost:5173       sushigo_agent_c

Next steps:
  Start all agents:        ./scripts/init.sh
  Start one agent:         ./scripts/init.sh agent-a
  Add another agent:       ./scripts/create-agent.sh
  Reset agent database:    ./scripts/reset-agent-db.sh agent-a
```

---

## Scripts

### `setup.sh` — full initialization

```bash
./scripts/setup.sh --agents=3
./scripts/setup.sh --agents=2 --repo=git@github.com:pakodiazdev/sushigo.git
```

Clones SushiGo N times, generates isolated `.env` files, creates one PostgreSQL database per agent, runs `composer install`, `npm install`, and `php artisan migrate --seed` for each. Idempotent — safe to re-run.

---

### `init.sh` — start agents

```bash
./scripts/init.sh             # start all agents (each in a tmux window)
./scripts/init.sh agent-a     # start one agent (foreground, Overmind output)
```

Single-agent mode runs in the foreground so you see Overmind's live output. Ctrl+C cleanly stops both Laravel and Vite. All-agents mode opens each in a named tmux window — attach with `tmux attach -t agent-a`.

---

### `create-agent.sh` — add an agent

```bash
./scripts/create-agent.sh
```

Auto-detects the next available letter and port. Creates a new clone, database, and `.env` without touching existing agents.

---

### `reset-agent-db.sh` — reset one database

```bash
./scripts/reset-agent-db.sh agent-b
```

Drops `sushigo_agent_b`, recreates it, and runs `migrate --seed`. Other agents are untouched and keep running.

---

### Makefile shortcuts

```bash
make up                        # docker compose up -d
make down                      # docker compose down
make init                      # ./scripts/init.sh
make init AGENT=agent-a        # ./scripts/init.sh agent-a
make reset-db AGENT=agent-a    # ./scripts/reset-agent-db.sh agent-a
make logs                      # docker compose logs -f
```

---

## Day-to-day workflow

**Switch branch in an agent:**
```bash
cd agents/sushigo-agent-b
git fetch origin
git checkout feature/065-new-feature
```

**Restart only Laravel (without stopping Vite):**
```bash
# Inside the agent's Overmind session:
overmind restart web
```

**Check what's running across all agents:**
```bash
tmux ls
# agent-a: 1 windows
# agent-b: 1 windows
```

**Stop all agents:**
```bash
tmux kill-server
```

**Run Cypress against a specific agent:**
```bash
cd agents/sushigo-agent-a
CYPRESS_BASE_URL=http://localhost:5171 npx cypress open
```

---

## Shared services

| Service | URL | Purpose |
|---|---|---|
| PostgreSQL | `localhost:5432` | Database for all agents |
| Redis | `localhost:6379` | Cache / queues |
| Mailpit | http://localhost:8025 | Email UI (catches all outbound mail) |

All agents connect to the same PostgreSQL instance but use isolated databases (`sushigo_agent_a`, `sushigo_agent_b`, ...). Redis is shared — cache keys are namespaced per agent via `CACHE_PREFIX` in each `.env`.

---

## Project context

**sushigo-dev-lab** is part of the [SushiGo](https://github.com/pakodiazdev/sushigo) project — a full-stack tenant platform built with:

- **Backend:** Laravel 12 · Passport OAuth · Spatie Permissions · PostgreSQL
- **Frontend:** React 19 · TanStack Router/Query · Zustand · Tailwind CSS
- **Mobile:** Flutter (in progress)

This lab was designed specifically to support AI-assisted parallel development (Claude Code, Copilot, Codex) — where multiple agents work different branches concurrently and a human reviews, tests, and merges.

---

## Documentation

- [Architecture decisions](docs/architecture.md) — why shared services, why Overmind, port strategy
- [Working with agents](docs/agents.md) — branches, Overmind commands, database resets
- [Troubleshooting](docs/troubleshooting.md) — port conflicts, DB errors, PHP version issues, Vite CORS

---

## License

MIT
