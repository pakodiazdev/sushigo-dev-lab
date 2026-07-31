# Workspace Reference

Each workspace is an independent clone of the sushigo repository with its own database, ports, and git branch.

## What is a workspace?

A workspace is a full working environment for one branch of sushigo. Multiple workspaces can run in parallel — each completely isolated from the others.

```
workspaces/
├── sushigo-a/    ← clone on branch feature/065-my-feature
├── sushigo-b/    ← clone on branch main
└── sushigo-c/    ← clone on branch feature/066-another-feature
```

## Workspace slots

| Workspace | APP_PORT | VITE_PORT | Database |
|---|---|---|---|
| sushigo-a | 8001 | 5171 | sushigo_ws_a |
| sushigo-b | 8002 | 5172 | sushigo_ws_b |
| sushigo-c | 8003 | 5173 | sushigo_ws_c |
| sushigo-d | 8004 | 5174 | sushigo_ws_d |
| sushigo-e | 8005 | 5175 | sushigo_ws_e |
| sushigo-f | 8006 | 5176 | sushigo_ws_f |
| sushigo-g | 8007 | 5177 | sushigo_ws_g |
| sushigo-h | 8008 | 5178 | sushigo_ws_h |

Slots are assigned automatically in order. You can have up to 8 workspaces running simultaneously.

## Workspace directory layout

```
workspaces/sushigo-a/
├── .env                    ← workspace-level: APP_PORT, VITE_PORT, DB_DATABASE, WORKSPACE_ROOT
├── init-agent-workspace.sh ← boot script (from sushigo repo)
├── Procfile.dev            ← process definitions (from sushigo repo, patched by dev-lab)
└── code/
    ├── api/
    │   └── .env            ← Laravel env (DB_*, APP_URL, etc.)
    └── webapp/
```

## Creating workspaces

**First workspace (or full setup):**
```bash
./scripts/setup.sh --workspaces=2
./scripts/setup.sh --workspaces=1 --branch=feature/065-my-feature
```

**Add a workspace to an existing setup:**
```bash
./scripts/create-workspace.sh
./scripts/create-workspace.sh --branch=feature/066-another-feature
```

## Starting workspaces

**Single workspace (foreground — Overmind output visible):**
```bash
./scripts/init.sh sushigo-a
make init WORKSPACE=sushigo-a
```

**All workspaces (background):**
```bash
./scripts/init.sh
make init
```

## Stopping workspaces

**Single workspace:**
```bash
cd workspaces/sushigo-a && overmind stop
```

**All workspaces:**
```bash
for dir in workspaces/sushigo-*/; do
  [ -d "$dir" ] && (cd "$dir" && overmind stop 2>/dev/null || true)
done
```

**Shared services only:**
```bash
docker compose down
make down
```

## Working with a workspace

Once a workspace is running, use Overmind commands from within the workspace directory:

```bash
cd workspaces/sushigo-a

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

Each workspace is a regular git clone. To switch branches:

```bash
cd workspaces/sushigo-a
git fetch origin
git checkout feature/066-another-feature
```

If migrations changed on the new branch, reset the database:

```bash
./scripts/reset-workspace-db.sh sushigo-a
```

## Pulling latest changes

```bash
cd workspaces/sushigo-a
git pull origin feature/065-my-feature
```

If migrations were added:

```bash
cd workspaces/sushigo-a/code/api
php artisan migrate
```

## Updating all workspaces to main

```bash
./scripts/update-workspaces.sh
make update-workspaces
```

This checks out `main` and fast-forward pulls the latest changes in every `workspaces/sushigo-*/`
clone. A workspace with uncommitted changes is skipped and reported, never stashed or discarded.
A workspace whose branch has diverged from `origin/main` (non-fast-forward) is also skipped and
reported — resolve that one manually with a rebase or merge.

## Resetting a database

```bash
./scripts/reset-workspace-db.sh sushigo-a
make reset-db WORKSPACE=sushigo-a
```

This drops and recreates the database, then reruns all migrations and seeders. The agent process does not need to be stopped, but in-flight requests will see transient DB errors during the reset. If the server fails to reconnect on the next request, restart the workspace with `overmind restart web`.

## Deleting workspaces

```bash
./scripts/delete-workspace.sh sushigo-a
./scripts/delete-workspace.sh a
make delete-workspace WORKSPACE=sushigo-a
```

This stops the workspace's Overmind session if running, stops its E2E stack if running (`stop-e2e.sh` — the Vite E2E dev server and the `e2e-api-<letter>` container), terminates active connections and drops its databases (`sushigo_ws_<letter>`, `sushigo_ws_<letter>_test`, `sushigo_ws_<letter>_e2e`), then removes `workspaces/sushigo-<letter>`. It does not touch shared Docker services or any other workspace. Running it on a workspace that doesn't exist exits with an error and lists the available workspaces instead of silently doing nothing.

## Shared resources

Redis and Mailpit are shared across all workspaces:

| Service | URL |
|---|---|
| Mailpit UI | http://localhost:8025 |
| Redis | 127.0.0.1:6379 |

**Cache isolation:** each workspace's `code/api/.env` has a unique `CACHE_PREFIX` (e.g. `ws_a_`) set by `setup.sh` and `create-workspace.sh` to avoid Redis key collisions. If you configure a workspace manually, add `CACHE_PREFIX=ws_<letter>_` to `code/api/.env`.

**Mail capture:** all outbound mail from all workspaces lands in the same Mailpit inbox. Filter by recipient if needed.
