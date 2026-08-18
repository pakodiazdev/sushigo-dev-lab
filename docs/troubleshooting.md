# Troubleshooting

Every entry follows the same shape: a literal symptom heading, a one-line cause, and an
explicit fix. Search for the exact text you saw on screen.

## Shared services

### ❌ PostgreSQL did not become ready in time

**Cause:** Docker isn't running, or the `db` container is unhealthy and never passes its `pg_isready` check — `init.sh` hits the same cause but prints `❌ PostgreSQL not ready` instead.
**Fix:**
```bash
docker compose logs db
docker compose ps
```
If the volume itself is corrupted:
```bash
docker compose down -v   # destroys pgdata volume — all workspace DBs will need reset
docker compose up -d
```

### ❌ Cannot connect to PostgreSQL at 127.0.0.1:5432

**Cause:** the shared `db` service isn't running — both `reset-workspace-db.sh` and `delete-workspace.sh` check this and fail fast before doing anything (unlike `init.sh`, which starts `db` itself instead — see the entry above).
**Fix:**
```bash
docker compose up -d
psql postgresql://admin:admin@127.0.0.1:5432/postgres -c '\l'
```

### ❌ Redis connection refused

**Cause:** the shared `redis` service crashed or was never started.
**Fix:**
```bash
docker compose logs redis
docker compose restart redis
```

---

## pgAdmin

### ❌ Error response from daemon: ports are not available: exposing port TCP 127.0.0.1:5050

**Cause:** another process is already bound to `PGADMIN_HOST_PORT` (`5050` by default) — usually a pgAdmin container that's still running from a previous `make pgadmin`.
**Fix:** if pgAdmin is already up, stop it the supported way:
```bash
make pgadmin-stop
```
Only if `lsof -i :5050` shows something else genuinely unrelated — **never** `com.docker.backend`
or any other Docker process; killing that breaks port-forwarding for every running container, not
just pgAdmin:
```bash
lsof -ti :5050 | xargs -I {} kill -9 {}
```
Or use a different port entirely:
```bash
# In .env:
PGADMIN_HOST_PORT=5099
```

### ❌ pgAdmin stays `health: starting` for a long time

**Cause:** not necessarily a failure — pgAdmin's own startup is CPU-heavy and can take well past a minute on a loaded machine.
**Fix:** the container's `start_period` allows up to 60s before a failing check counts against
it, and this can take even longer on a machine already running several workspaces' Vite dev
servers — confirm it's still making progress rather than stuck or crashed:
```bash
docker compose logs pgadmin
# Look for "Added N Server(s)." followed by "Listening at: http://[::]:80"
```
If those lines are present, just wait — it'll flip to `healthy` shortly after. If `docker compose
ps pgadmin` instead shows it restarting repeatedly, `docker compose logs pgadmin` will show
where it's actually failing (a stack trace, not just a slow startup).

### ❌ pgAdmin's connection to the shared server fails after it was previously working

**Cause:** the actual PostgreSQL password drifted from `POSTGRES_PASSWORD` — usually a manual `ALTER ROLE` against the running `db` container, outside the dev-lab's own `.env` flow.
**Fix:** `docker/pgadmin/entrypoint.sh` only ever knows the password from `POSTGRES_PASSWORD`,
so its generated `.pgpass` doesn't track changes made any other way — make the two agree again,
either by reverting the manual change or updating `.env` to match, then recreate pgAdmin so it
regenerates `.pgpass` from the current value:
```bash
make pgadmin
```

---

## Workspace setup

### ❌ Required tool not found: overmind

**Cause:** `setup.sh` checks 8 prerequisite tools before doing any work and exits on the first one missing — the tool name in the message changes, install whichever one it names.
**Fix:** `status.sh` (`make status`) prints the same message but only ever checks for `overmind`
specifically, since it's the only external tool it shells out to:
```bash
brew install overmind
./scripts/setup.sh --workspaces=2
```

### ❌ `setup.sh` fails mid-run

**Cause:** any step after the prerequisite check (git clone, `composer install`, `npm install`,
migrations) can fail independently — the error is usually PHP/Node/DB-specific, not a `setup.sh`
bug.
**Fix:** `setup.sh` is safe to re-run — for existing workspace directories it skips cloning and
`.env` configuration, but still runs `composer install`, `npm install`, and `php artisan migrate`
to pick up dependency or schema changes. New workspaces are set up in full.
```bash
./scripts/setup.sh --workspaces=2
```

### ❌ composer install: memory exhausted

**Cause:** PHP's default memory limit is too low for Composer's dependency resolver on this
project's package graph.
**Fix:**
```bash
cd workspaces/sushigo-a/code/api
COMPOSER_MEMORY_LIMIT=-1 composer install
```

### ❌ npm install fails or leaves a broken node_modules

**Cause:** an interrupted install, or a local Node/npm version mismatch, corrupted
`node_modules`.
**Fix:**
```bash
cd workspaces/sushigo-a/code/webapp
rm -rf node_modules
npm install
```

### ❌ Database already exists — skipping

**Cause:** not an error — `setup.sh` and `create-workspace.sh` print this and move on when a
workspace's database is already there from a previous run.
**Fix:** only act on this if you actually want a clean database:
```bash
./scripts/reset-workspace-db.sh sushigo-a
```

### ❌ All workspace slots (a–h) are already in use

**Cause:** `create-workspace.sh` only manages 8 slots, `a` through `h`.
**Fix:** free a slot with the supported delete workflow — it stops Overmind, drops the
workspace's databases, and removes the directory, so nothing is left half-cleaned:
```bash
make delete-workspace WORKSPACE=sushigo-h
./scripts/create-workspace.sh --branch=feature/my-new-feature
```

---

## Starting and stopping workspaces

### ❌ overmind: error: already running

**Cause:** an Overmind *session* for this workspace is still alive — `overmind stop` only stops
its processes, not the session itself, so a session left that way (or from a prior foreground
run) still holds the socket and refuses a new `overmind start`.
**Fix:** quit the session outright, not just its processes:
```bash
cd workspaces/sushigo-a && overmind quit
```

### ❌ listen tcp 0.0.0.0:8001: bind: address already in use

**Cause:** another process — often a leftover Overmind session from a previous run — is already
holding the workspace's PHP or Vite port.
**Fix:**
```bash
lsof -ti :8001 | xargs -I {} kill -9 {}
```
Or, if it's a stale Overmind session for that same workspace — `overmind stop` alone won't
release it, only `overmind quit` does:
```bash
cd workspaces/sushigo-a && overmind quit
```

### ❌ Failed to stop Overmind cleanly — workspace processes may still be running

**Cause:** `overmind quit` failed inside `delete-workspace.sh`, which warns instead of aborting — a PHP or Vite process for that workspace may be orphaned.
**Fix:** the database drop and directory removal still complete regardless. `make down` can leave
the same kind of orphaned process behind, but won't show this warning for it — it swallows
`overmind quit` failures silently and always reports `✅ All services stopped`. Either way, find
and kill whatever is still bound to that workspace's ports:
```bash
lsof -ti :8001,5171 | xargs -I {} kill -9 {}   # use the workspace's actual APP_PORT/VITE_PORT
```

---

## Runtime errors

### ❌ Laravel 500 on first request

**Cause:** varies — check the log first.
**Fix:**
```bash
tail -50 workspaces/sushigo-a/code/api/storage/logs/laravel.log
```
Common causes:
- **Missing APP_KEY**: `cd workspaces/sushigo-a/code/api && php artisan key:generate`
- **Database not migrated**: `php artisan migrate --force`
- **Wrong DB credentials**: check `code/api/.env` — `DB_HOST` must be `127.0.0.1`, not `pgsql`

### ❌ Vite HMR not working

**Cause:** the workspace's `.env` is missing (or has the wrong) `VITE_PORT`, or Vite lost its
bind to `0.0.0.0` after a restart.
**Fix:** check what's actually there first:
```bash
cat workspaces/sushigo-a/.env
# Should show: VITE_PORT=5171 (this workspace's assigned port)
```
If `VITE_PORT` is missing or wrong, restore it before restarting — `init.sh` sources this file
as-is and `Procfile.dev` falls back to `5173` when it's absent, so a plain restart alone won't
fix it. The assigned port is `5171 + slot index` (`a`=5171, `b`=5172, ...) unless overridden by
`VITE_PORT_<LETTER>` in `tools.env`:
```bash
grep -q '^VITE_PORT=' workspaces/sushigo-a/.env \
  && sed -i '' 's|^VITE_PORT=.*|VITE_PORT=5171|' workspaces/sushigo-a/.env \
  || echo 'VITE_PORT=5171' >> workspaces/sushigo-a/.env
```
Then restart the whole session, not just the process — `overmind restart` only restarts a
process within the *existing* session, which still has the old (missing/wrong) `VITE_PORT`
baked into its own environment from when it was launched; only re-running `init.sh` re-sources
the corrected `.env`:
```bash
(cd workspaces/sushigo-a && overmind quit)
./scripts/init.sh sushigo-a
```

### ❌ Frontend can't reach the API

**Cause:** `code/webapp/.env`'s `VITE_API_URL` is stale, usually after the workspace's API port
changed.
**Fix:**
```bash
grep VITE_API_URL workspaces/sushigo-a/code/webapp/.env
# Should show: VITE_API_URL=http://localhost:8001/api/v1 (workspace's actual APP_PORT)
```
If it doesn't match, edit it directly — re-running `setup.sh` won't help here, it only writes
`code/webapp/.env` for a workspace it's creating fresh, never for one that already exists:
```bash
sed -i '' 's|^VITE_API_URL=.*|VITE_API_URL=http://localhost:8001/api/v1|' \
  workspaces/sushigo-a/code/webapp/.env
```
Then restart:
```bash
cd workspaces/sushigo-a && overmind restart vite
```

---

## Database issues

### ❌ Migrations fail after switching branches

**Cause:** the new branch adds migrations that conflict with, or are missing from, the
workspace's current schema.
**Fix:**
```bash
cd workspaces/sushigo-a/code/api
php artisan migrate --force
```
If migrations conflict outright (e.g. schema mismatch from rebased history), don't fight it —
reset:
```bash
./scripts/reset-workspace-db.sh sushigo-a
```

### ❌ Seeder fails with a unique constraint violation

**Cause:** a seeder isn't idempotent. Project convention is `updateOrCreate()` — a seeder using
plain `create()` fails the second time it runs against the same database.
**Fix:**
```bash
./scripts/reset-workspace-db.sh sushigo-a
```
If the same seeder keeps failing on a freshly reset database, that's the actual bug — fix it to
use `updateOrCreate()`.

### ❌ SQLSTATE[40P01]: deadlock detected running php artisan test

**Cause:** the workspace predates per-workspace test databases and still points `.env.testing` at a shared one — two workspaces running `php artisan test` at the same time then deadlock on it.
**Fix:** every workspace created since gets its own isolated `sushigo_ws_<letter>_test` (see
`scripts/lib/workspace-bootstrap.sh`) — if you still see this, the workspace needs its
`.env.testing` regenerated:
```bash
cd workspaces/sushigo-a/code/api
cp .env .env.testing
sed -i '' 's|^DB_DATABASE=.*|DB_DATABASE=sushigo_ws_a_test|' .env.testing
psql -h 127.0.0.1 -U admin -d postgres -c "CREATE DATABASE sushigo_ws_a_test;"
```

---

## Tool tokens

### ❌ Missing SONAR_TOKEN_WEBAPP and SONAR_TOKEN_API environment variables

**Cause:** `.env` files are read by the Laravel/Vite dotenv loaders, not by your shell — a plain
terminal or a Claude Code Bash session never sources them automatically, even though
`setup.sh`/`create-workspace.sh` already wrote `SONAR_TOKEN_API`/`SONAR_TOKEN_WEBAPP` into
`workspaces/sushigo-<x>/.env`.
**Fix:** verify they're actually there:
```bash
grep SONAR workspaces/sushigo-a/.env
```
Export them into the current shell before running tools that expect real env vars (e.g. the
`/sonar-review` Claude Code skill):
```bash
export $(grep -E '^SONAR_TOKEN_(API|WEBAPP)=' workspaces/sushigo-a/.env | xargs)
```
If the tokens are missing from the workspace `.env` entirely, set `SONAR_TOKEN` in the dev-lab
root `.env` (gitignored, one token covers both SonarCloud projects) and re-run
`./scripts/setup.sh` or `./scripts/create-workspace.sh` — both upsert `SONAR_TOKEN_API`/
`SONAR_TOKEN_WEBAPP` into every existing workspace's `.env`.

---

## Cleanup

### ❌ Need to remove one workspace completely

**Cause:** n/a — routine cleanup.
**Fix:** use the supported delete workflow. It stops Overmind, stops the E2E stack, drops all
three of the workspace's databases (dev, test, e2e), and removes the directory — nothing to do
by hand:
```bash
make delete-workspace WORKSPACE=sushigo-c
```

### ❌ Need to remove every workspace

**Cause:** n/a — routine cleanup. There's no bulk-delete command yet, so loop over the
per-workspace script instead of deleting directories and databases by hand.
**Fix:**
```bash
for ws in workspaces/sushigo-*/; do
  [ -d "$ws" ] || continue   # no-op when the glob doesn't match anything
  ./scripts/delete-workspace.sh "$(basename "$ws")"
done
```

### ❌ Need a full reset (start from scratch)

**Cause:** n/a — tears down both workspaces and shared infrastructure.
**Fix:**
```bash
make down                # stop every Overmind session + shared Docker services
rm -rf workspaces/
docker compose down -v   # destroys the pgdata volume
docker compose up -d
./scripts/setup.sh --workspaces=2
```
