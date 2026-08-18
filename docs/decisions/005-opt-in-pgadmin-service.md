# ADR-005: Opt-in pgAdmin service under the `tools` Compose profile

> **Status:** Accepted
> **Date:** 2026-08-17
> **Deciders:** pakodiazdev

---

## Context

Every workspace has isolated development, test, and E2E databases in the shared PostgreSQL container. Inspecting them required either raw `psql` commands or manually configuring an external GUI client with the lab's host, port, and credentials by hand. Database inspection is useful during feature work and debugging, but a GUI does not need to run — and consume resources — during every session, so it needed to stay off the lab's lightweight default footprint while still being a single command away when wanted.

---

## Decision

Add a `pgadmin` service to `docker-compose.yml` under the optional `tools` Compose profile, pinned to `dpage/pgadmin4:9.14.0` and bound to `127.0.0.1:${PGADMIN_HOST_PORT:-5050}`. It runs in pgAdmin's desktop mode (no login page, no master-password prompt) with Postfix disabled, since this is a host-only instance that never sends account email. `docker/pgadmin/entrypoint.sh` regenerates the server definition (`servers.json`) and the `.pgpass` file from `POSTGRES_USER`/`POSTGRES_PASSWORD` on **every** container start — not only the first — before handing off to the image's own entrypoint, so a credential rotation on an already-initialized `pgadmin-data` volume is still picked up. `PGADMIN_REPLACE_SERVERS_ON_STARTUP` re-imports that definition into pgAdmin's internal server list on every start for the same reason. `make pgadmin` / `make pgadmin-stop` start and stop only this service.

---

## Considered Options

### Option 1: Document manual `psql` / external GUI configuration

**Pros:**
- No new service to build or maintain

**Cons:**
- Every developer re-derives host/port/credentials by hand, from raw `psql` output or by reading `docker-compose.yml`
- No visual browser for the growing set of `sushigo_ws_<letter>[_test|_e2e]` databases

---

### Option 2: Always-on pgAdmin in the default service set

Add `pgadmin` as a normal service, started by every `docker compose up -d`.

**Pros:**
- No extra command to remember — always available

**Cons:**
- Runs a full web app on every developer's machine for every session, even when nobody is inspecting a database that day — against the lab's lightweight-by-default philosophy for shared infrastructure

---

### Option 3: Opt-in service behind the `tools` Compose profile ✅ *(chosen)*

`pgadmin` gets `profiles: [tools]`, so `docker compose up -d` never starts it; `make pgadmin` (`docker compose --profile tools up -d pgadmin`) does. `make pgadmin-stop` stops only this service.

**Pros:**
- Zero footprint in the default developer session — matches how the lab already treats E2E infrastructure (see [ADR-004](004-per-slot-e2e-infrastructure.md)) as opt-in, on-demand infrastructure
- Preconfigured connection (host, port, and credentials pulled from the same env vars the `db` service already uses) means opening it requires no manual client setup
- Credentials are always read as runtime environment variables at container start, sourced from the gitignored root `.env` — a real credential override never needs to be committed (only the `admin`/`admin` local-dev fallback baked into `docker-compose.yml`'s `${POSTGRES_PASSWORD:-admin}` default is; this PR added the repo's first root `.env.example`)

**Cons:**
- One more Make target and one more opt-in concept for a new contributor to discover, versus something that "just works" on `docker compose up`

---

## Implementation notes (what actually shipped)

Three non-obvious constraints shaped the final implementation, beyond the original proposal in issue #68:

- **`servers.json` location.** The image's default location (`/pgadmin4/servers.json`) is owned by `root` and not writable by the `pgadmin` user the container actually runs as. The server definition is written instead to `/var/lib/pgadmin/servers.json` — the persisted, writable volume — via `PGADMIN_SERVER_JSON_FILE`.
- **`.local` email domain.** `PGADMIN_DEFAULT_EMAIL=dev@sushigo.local` is rejected outright by pgAdmin's default reserved-TLD list. `PGADMIN_CONFIG_ALLOW_SPECIAL_EMAIL_DOMAINS: "['local']"` explicitly allows it rather than switching to a real-looking domain for a bootstrap-only, non-authenticating account.
- **`.pgpass` regeneration timing.** The base image only copies its `PGPASS_FILE` into place on first boot (when its internal SQLite store doesn't exist yet). On a volume that's already initialized, a later PostgreSQL credential change would never reach the stored `.pgpass`. `docker/pgadmin/entrypoint.sh` regenerates both `servers.json` and `.pgpass` unconditionally on every container start instead of relying on the image's first-boot-only behavior.

---

## Consequences

**Positive:**
- `make pgadmin` opens a working, password-free connection to the shared PostgreSQL instance with zero manual client configuration, listing every `sushigo_ws_<letter>` / `_test` / `_e2e` database
- pgAdmin is bound to loopback only — never exposed beyond the host
- `make pgadmin-stop` leaves `db`, `redis`, `mailpit`, and all running workspaces untouched
- A `pgadmin-data` named volume preserves preferences and connection history across container recreation, while `entrypoint.sh` still keeps the *server definition and password* fresh on every start

**Negative / trade-offs:**
- A second custom entrypoint script (`docker/pgadmin/entrypoint.sh`) is now a maintenance surface tied to the exact behavior of the upstream `dpage/pgadmin4` image's own `/entrypoint.sh` — an upstream image change to that startup contract could require updating this script

**Neutral:**
- This PR added the repo's first root `.env.example`, establishing the pattern for documenting `docker-compose.yml`-level overrides (`POSTGRES_*`, `PGADMIN_*`) going forward

---

## Requirements Addressed

| ID | Description | Type |
|----|-------------|------|
| — | `make pgadmin` must start pgAdmin without it being part of the default service set | Functional |
| — | Opening the pgAdmin URL must require no login and show a preconfigured, working connection to the shared PostgreSQL service | Functional |
| — | Every `sushigo_ws_<letter>` database, including its `_test` and `_e2e` variants, must be browsable through that connection | Functional |
| — | `make pgadmin-stop` must stop only pgAdmin, leaving PostgreSQL, Redis, Mailpit, and all workspaces untouched | Functional |
| — | pgAdmin must bind to the loopback interface only | Non-functional |
| — | PostgreSQL credentials must come from runtime environment variables; any real (non-default) credential must live only in the gitignored root `.env`, never committed | Non-functional |
| — | A PostgreSQL credential change followed by service recreation must refresh the managed connection automatically | Non-functional |
| — | pgAdmin preferences must survive container recreation | Non-functional |
| — | `docker compose --profile tools config --quiet` must pass | Non-functional |

---

## Links

- Related issue: [#68 — Add opt-in pgAdmin service for browsing the shared PostgreSQL instance](https://github.com/pakodiazdev/sushigo-dev-lab/issues/68)
- Implemented in PR: [#75](https://github.com/pakodiazdev/sushigo-dev-lab/pull/75)
- Related ADR: [ADR-004 — Per-slot E2E infrastructure](004-per-slot-e2e-infrastructure.md) (same opt-in, profile-gated pattern for non-default infrastructure)
