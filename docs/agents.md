# Agent Reference

Each agent is an independent clone of the sushigo repository with its own database, ports, and git branch.

## What is an agent?

An agent is a full working environment for one branch of sushigo. Multiple agents can run in parallel — each completely isolated from the others.

```
agents/
├── sushigo-agent-a/    ← clone on branch feature/065-my-feature
├── sushigo-agent-b/    ← clone on branch main
└── sushigo-agent-c/    ← clone on branch feature/066-another-feature
```

## Agent slots

| Agent | APP_PORT | VITE_PORT | Database |
|---|---|---|---|
| agent-a | 8001 | 5171 | sushigo_agent_a |
| agent-b | 8002 | 5172 | sushigo_agent_b |
| agent-c | 8003 | 5173 | sushigo_agent_c |
| agent-d | 8004 | 5174 | sushigo_agent_d |
| agent-e | 8005 | 5175 | sushigo_agent_e |
| agent-f | 8006 | 5176 | sushigo_agent_f |
| agent-g | 8007 | 5177 | sushigo_agent_g |
| agent-h | 8008 | 5178 | sushigo_agent_h |

Slots are assigned automatically in order. You can have up to 8 agents running simultaneously.

## Agent directory layout

```
agents/sushigo-agent-a/
├── .env                    ← agent-level: APP_PORT, VITE_PORT, DB_DATABASE
├── init-agent-workspace.sh ← boot script (from sushigo repo)
├── Procfile.dev            ← process definitions (from sushigo repo)
└── code/
    ├── api/
    │   └── .env            ← Laravel env (DB_*, APP_URL, etc.)
    └── webapp/
```

## Creating agents

**First agent (or full setup):**
```bash
./scripts/setup.sh --agents=2
./scripts/setup.sh --agents=1 --branch=feature/065-my-feature
```

**Add an agent to an existing setup:**
```bash
./scripts/create-agent.sh
./scripts/create-agent.sh --branch=feature/066-another-feature
```

## Starting agents

**Single agent (foreground — Overmind output visible):**
```bash
./scripts/init.sh agent-a
make init AGENT=agent-a
```

**All agents (background):**
```bash
./scripts/init.sh
make init
```

## Stopping agents

**Single agent:**
```bash
cd agents/sushigo-agent-a && overmind stop
```

**All agents:**
```bash
for dir in agents/sushigo-agent-*/; do
  [ -d "$dir" ] && (cd "$dir" && overmind stop 2>/dev/null || true)
done
```

**Shared services only:**
```bash
docker compose down
make down
```

## Working with an agent

Once an agent is running, use Overmind commands from within the agent directory:

```bash
cd agents/sushigo-agent-a

# View logs for all processes
overmind echo

# Attach to one process (Ctrl+B then D to detach)
overmind connect web
overmind connect vite

# Restart one process
overmind restart web
overmind restart vite

# Stop everything
overmind stop
```

## Changing branch

Each agent is a regular git clone. To switch branches:

```bash
cd agents/sushigo-agent-a
git fetch origin
git checkout feature/066-another-feature
```

If migrations changed on the new branch, reset the database:

```bash
./scripts/reset-agent-db.sh agent-a
```

## Pulling latest changes

```bash
cd agents/sushigo-agent-a
git pull origin feature/065-my-feature
```

If migrations were added:

```bash
cd agents/sushigo-agent-a/code/api
php artisan migrate
```

## Resetting a database

```bash
./scripts/reset-agent-db.sh agent-a
make reset-db AGENT=agent-a
```

This drops and recreates the database, then reruns all migrations and seeders. The agent process does not need to be stopped, but in-flight requests will see transient DB errors during the reset. If the server fails to reconnect on the next request, restart the agent with `overmind restart web`.

## Shared resources

Redis and Mailpit are shared across all agents:

| Service | URL |
|---|---|
| Mailpit UI | http://localhost:8025 |
| Redis | 127.0.0.1:6379 |

**Cache isolation:** each agent's `code/api/.env` has a unique `CACHE_PREFIX` (e.g. `agent_a_`) set by `setup.sh` and `create-agent.sh` to avoid Redis key collisions. If you configure an agent manually, add `CACHE_PREFIX=agent_<letter>_` to `code/api/.env`.

**Mail capture:** all outbound mail from all agents lands in the same Mailpit inbox. Filter by recipient if needed.
