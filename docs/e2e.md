# E2E Testing

E2E tests use Cypress and run against a lightweight PHP container with an isolated database, connected to a Vite dev server on a separate port. This keeps tests completely decoupled from the normal workspace dev server.

## Architecture

```
┌─────────────────────────────────────────────────────┐
│ devlab host                                         │
│                                                     │
│  Vite E2E (port 5181)  ──→  Browser under test      │
│         ↑                                           │
│  CYPRESS_baseUrl                                    │
│                                                     │
│  Cypress (local)  ──→  docker exec  ──→  e2e-api-a  │
│         ↑                                  ↑        │
│  CYPRESS_container              sushigo_ws_a_e2e DB  │
└─────────────────────────────────────────────────────┘
```

| Component | What it is |
|---|---|
| `e2e-api-a` | PHP 8.3 container, `APP_ENV=testing`, no cache, isolated DB |
| `sushigo_ws_a_e2e` | Separate PostgreSQL database — never shares state with dev DB |
| Vite E2E server | Same webapp, different port, `VITE_API_URL` points to the container |
| Cypress | Runs locally on your machine (not inside Docker) |

## Running E2E (devlab)

### 1 — Start shared services (once per session)

```bash
make up
```

### 2 — Start the E2E stack for a workspace

```bash
make e2e WORKSPACE=sushigo-a
```

This does everything automatically:
- Builds and starts the `e2e-api-a` Docker container
- Creates the `sushigo_ws_a_e2e` database
- Runs `migrate` + `db:seed`
- Launches a Vite dev server on port `5181`

### 3a — Open Cypress GUI (interactive)

```bash
make cypress WORKSPACE=sushigo-a
```

Opens the Cypress Test Runner. Pick a spec to run individually.

### 3b — Run all tests headless

```bash
make cypress-run WORKSPACE=sushigo-a
```

Runs all specs in terminal output mode (no browser UI). Use this for full-suite validation.

### 4 — Stop the E2E stack

```bash
make e2e-stop WORKSPACE=sushigo-a
```

Stops the container and the Vite E2E process.

---

## Port assignments per workspace

| Workspace | E2E API port | Vite E2E port | E2E database |
|---|---|---|---|
| sushigo-a | 8901 | 5181 | sushigo_ws_a_e2e |
| sushigo-b | 8902 | 5182 | sushigo_ws_b_e2e |
| sushigo-c | 8903 | 5183 | sushigo_ws_c_e2e |
| sushigo-d | 8904 | 5184 | sushigo_ws_d_e2e |

Ports can be overridden in `tools.env`:

```bash
E2E_API_PORT_A=8901
E2E_VITE_PORT_A=5181
```

---

## Environment variables passed to Cypress

`make cypress` and `make cypress-run` automatically resolve and set:

| Variable | Value | Purpose |
|---|---|---|
| `CYPRESS_baseUrl` | `http://localhost:<vite-port>` | URL Cypress visits |
| `CYPRESS_container` | `sushigo-dev-lab-e2e-api-a-1` | Container for `cy.task()` artisan calls |

These map to values in `cypress.config.ts`:

```ts
const CONTAINER = process.env.CYPRESS_container || 'devtest_container'
baseUrl: process.env.CYPRESS_baseUrl || 'https://devtest.sushigo.local'
```

---

## Running against devtest (non-devlab)

When running Cypress directly from the webapp without devlab, the defaults in `cypress.config.ts` apply:

```bash
cd workspaces/sushigo-a/code/webapp

# Default: hits devtest environment
npm run cypress:open
npm run cypress:run
```

| Variable | Default value |
|---|---|
| `CYPRESS_baseUrl` | `https://devtest.sushigo.local` |
| `CYPRESS_container` | `devtest_container` |

To override manually:

```bash
CYPRESS_baseUrl=https://staging.sushigo.com \
CYPRESS_container=staging_container \
  npm run cypress:run
```

---

## Resetting test data inside a spec

```ts
// Full reset — slow (~30s), use only when schema changes
cy.task('db:reset')

// Fast reset — truncate + seed (~3-5s), preferred
cy.task('test:reset')
cy.task('test:reset', 'attendance')
cy.task('test:reset', 'attendance,cash')

// Seed only (schema already fresh)
cy.task('db:seed')
```

> **Note:** `cy.task()` calls `docker exec <CYPRESS_container> php artisan ...`  
> In the devlab E2E container, artisan is at `/app/artisan` (not `/app/code/api/artisan`  
> as in the devtest container). If tasks fail, check this path in `cypress.config.ts`.

---

## Troubleshooting

### ❌ E2E stack for sushigo-a is not running
**Cause:** `make cypress` was run before `make e2e`.  
**Fix:**
```bash
make e2e WORKSPACE=sushigo-a
```

### ❌ Container e2e-api-a did not become ready in time
**Cause:** Docker build failed or container crashed on start.  
**Fix:**
```bash
docker logs sushigo-dev-lab-e2e-api-a-1
```

### ❌ Vite E2E did not start in time
**Cause:** Port conflict or missing `node_modules`.  
**Fix:**
```bash
# Check port
lsof -i :5181

# Install deps if missing
npm --prefix workspaces/sushigo-a/code/webapp install
```

### ❌ cy.task('test:reset') fails with "artisan not found"
**Cause:** The devlab E2E container mounts `code/api` at `/app`, so artisan is at  
`/app/artisan` — not `/app/code/api/artisan` as in the devtest container.  
**Fix:** Update `cypress.config.ts` in the sushigo repo to use a configurable artisan path.
