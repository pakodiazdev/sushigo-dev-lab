# Troubleshooting

## Shared services

### PostgreSQL won't start

```
❌ PostgreSQL did not become ready in time
```

Check Docker is running, then inspect the container:

```bash
docker compose logs db
docker compose ps
```

If the volume is corrupted:

```bash
docker compose down -v   # destroys pgdata volume — all workspace DBs will need reset
docker compose up -d
```

### Cannot connect to PostgreSQL

```
❌ Cannot connect to PostgreSQL at 127.0.0.1:5432
```

The shared services container is not running:

```bash
docker compose up -d
```

Verify connectivity:

```bash
psql postgresql://admin:admin@127.0.0.1:5432/postgres -c '\l'
```

### Redis unavailable

```bash
docker compose logs redis
docker compose restart redis
```

---

## Workspace setup

### `setup.sh` fails mid-run

`setup.sh` is safe to re-run — for existing workspace directories it skips cloning and `.env` configuration, but still runs `composer install`, `npm install`, and `php artisan migrate` to pick up any dependency or schema changes. New workspaces are set up in full. Fix the underlying error, then run again:

```bash
./scripts/setup.sh --workspaces=2
```

### Composer install fails

```
composer install: memory exhausted
```

Increase PHP memory limit for the install:

```bash
cd workspaces/sushigo-a/code/api
php -d memory_limit=-1 /usr/local/bin/composer install
```

### npm install fails

If `node_modules` is in a bad state:

```bash
cd workspaces/sushigo-a/code/webapp
rm -rf node_modules package-lock.json
npm install
```

### Database already exists

```
ℹ️  Database already exists — skipping
```

Not an error. If you need a clean database:

```bash
./scripts/reset-workspace-db.sh sushigo-a
```

### All workspace slots are in use

```
❌ All workspace slots (a–h) are already in use.
```

Remove an unused workspace directory:

```bash
rm -rf workspaces/sushigo-h
./scripts/create-workspace.sh --branch=feature/my-new-feature
```

---

## Starting workspaces

### Overmind not found

```
❌ Overmind not found. Install with: brew install overmind
```

```bash
brew install overmind
```

### Procfile.dev not found

```
❌ Procfile.dev not found.
```

The sushigo clone is missing `Procfile.dev`. Make sure your branch is up to date with `main` (it was added in issue #144):

```bash
cd workspaces/sushigo-a
git fetch origin
git merge origin/main
```

### Port already in use

```
Error: listen tcp 0.0.0.0:8001: bind: address already in use
```

Another process is using the port. Find and stop it:

```bash
lsof -ti :8001 | xargs kill -9
```

Or check if another Overmind instance is already running for that workspace:

```bash
cd workspaces/sushigo-a && overmind stop
```

### Overmind already running

```
overmind: error: already running
```

Stop the existing instance first:

```bash
cd workspaces/sushigo-a && overmind stop
```

---

## Runtime errors

### Laravel 500 on first request

Check the Laravel log:

```bash
tail -50 workspaces/sushigo-a/code/api/storage/logs/laravel.log
```

Common causes:

- **Missing APP_KEY**: `cd workspaces/sushigo-a/code/api && php artisan key:generate`
- **Database not migrated**: `php artisan migrate --force`
- **Wrong DB credentials**: check `code/api/.env` — `DB_HOST` must be `127.0.0.1`, not `pgsql`

### Vite HMR not working

The webapp is served from a different port than the API. Make sure `VITE_PORT` is set in the workspace's `.env` and Vite started with `--host 0.0.0.0`:

```bash
cat workspaces/sushigo-a/.env
# Should show: VITE_PORT=5171
```

Restart Vite:

```bash
cd workspaces/sushigo-a && overmind restart vite
```

### Frontend can't reach the API

The webapp reads `VITE_API_URL` from its `.env`. If the API port changed, update `code/webapp/.env.local`:

```
VITE_API_URL=http://127.0.0.1:8001
```

---

## Database issues

### Migrations fail after branch switch

When switching to a branch with new migrations:

```bash
cd workspaces/sushigo-a/code/api
php artisan migrate --force
```

If migrations conflict (e.g. schema mismatch from rebased history):

```bash
./scripts/reset-workspace-db.sh sushigo-a
```

### Seeder errors

If a seeder fails with a unique constraint violation:

```bash
./scripts/reset-workspace-db.sh sushigo-a
```

Seeders use `updateOrCreate()` by convention — if yours doesn't, that's the bug.

---

## Tool tokens

### `SONAR_TOKEN_WEBAPP` / `SONAR_TOKEN_API` not found in an agent or terminal session

```
❌ Missing SONAR_TOKEN_WEBAPP and SONAR_TOKEN_API environment variables.
```

Not a copy failure — `setup.sh`/`create-workspace.sh` already propagate `SONAR_TOKEN` from
the dev-lab root `.env` into every `workspaces/sushigo-<x>/.env` as `SONAR_TOKEN_API` and
`SONAR_TOKEN_WEBAPP` (see `scripts/setup.sh` and `scripts/create-workspace.sh`). Verify they're
actually there:

```bash
grep SONAR workspaces/sushigo-a/.env
```

The real gap: `.env` files are read by the Laravel/Vite dotenv loaders, not by your shell — a
plain terminal or a Claude Code Bash session never sources them automatically. Export them into
the current shell before running tools that expect real env vars (e.g. the `/sonar-review`
Claude Code skill):

```bash
export $(grep -E '^SONAR_TOKEN_(API|WEBAPP)=' workspaces/sushigo-a/.env | xargs)
```

If the tokens are missing from the workspace `.env` entirely, set `SONAR_TOKEN` in the dev-lab
root `.env` (gitignored, one token covers both SonarCloud projects) and re-run
`./scripts/setup.sh` or `./scripts/create-workspace.sh` — both upsert `SONAR_TOKEN_API` /
`SONAR_TOKEN_WEBAPP` into every existing workspace's `.env`.

---

## Cleanup

### Remove one workspace completely

```bash
rm -rf workspaces/sushigo-c
psql postgresql://admin:admin@127.0.0.1:5432/postgres -c "DROP DATABASE sushigo_ws_c;"
```

### Remove all workspaces

```bash
rm -rf workspaces/
psql postgresql://admin:admin@127.0.0.1:5432/postgres <<'SQL'
DROP DATABASE IF EXISTS sushigo_ws_a;
DROP DATABASE IF EXISTS sushigo_ws_b;
DROP DATABASE IF EXISTS sushigo_ws_c;
DROP DATABASE IF EXISTS sushigo_ws_d;
SQL
```

### Full reset (start from scratch)

```bash
rm -rf workspaces/
docker compose down -v
docker compose up -d
./scripts/setup.sh --workspaces=2
```
