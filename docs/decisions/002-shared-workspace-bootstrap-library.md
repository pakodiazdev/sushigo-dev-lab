# ADR-002: Shared workspace-bootstrap library sourced by setup, create, and init

> **Status:** Accepted
> **Date:** 2026-07-25
> **Deciders:** pakodiazdev

---

## Context

`scripts/setup.sh` and `scripts/create-workspace.sh` each contained an independent, roughly 130-line copy of the same workspace bootstrap sequence: writing `code/api/.env` via seven `sed -i ''` calls, writing `code/webapp/.env`, writing the workspace-root `.env`, writing the `Procfile.dev` template, running `composer install` + `npm install`, and running `php artisan key:generate`, `passport:keys`, `migrate`, `db:seed`, and `l5-swagger:generate`. `scripts/init.sh` carried a third, separate copy of the `Procfile.dev` template in its own `write_procfile()` function.

Any change to the bootstrap sequence — a new `.env` key, a new install step — had to be applied by hand in every copy, or it would silently drift and break one path while the others kept working. The `Procfile.dev` template alone existed in three places across two files.

---

## Decision

Extract the shared logic into `scripts/lib/workspace-bootstrap.sh`, sourced by `setup.sh`, `create-workspace.sh`, and `init.sh`. Each function (`configure_api_env()`, `configure_webapp_env()`, `configure_workspace_env()`, `write_procfile()`, `mark_procfile_skip_worktree()`, `install_deps()`, `bootstrap_laravel()`) takes the workspace directory and any config it needs as explicit arguments — no global state — so callers stay independent of each other's internals.

---

## Considered Options

### Option 1: Leave the duplication in place, rely on discipline to keep the copies in sync

**Pros:**
- No refactor cost, no risk of behavior regressions

**Cons:**
- Already proven to drift — the three `Procfile.dev` copies existed precisely because "keep them in sync manually" had already failed once
- Every future bootstrap change requires N correct edits instead of one

---

### Option 2: Sourced shell library with argument-only functions ✅ *(chosen)*

Move the shared blocks into `scripts/lib/workspace-bootstrap.sh` as plain functions, sourced by each caller. No environment variables or caller-side globals are read implicitly inside the library.

**Pros:**
- The `Procfile.dev` template exists in exactly one place
- A future bootstrap change touches exactly one file
- Each caller (`setup.sh`, `create-workspace.sh`, `init.sh`) still controls its own control flow and error handling around the shared functions
- Testable in isolation with `shellcheck scripts/lib/*.sh`

**Cons:**
- Adds one more file callers must know to source
- Argument lists are longer at call sites than an implicit-global version would be — accepted as the cost of no hidden state

---

### Option 3: Convert the bootstrap sequence into a standalone script invoked via subprocess

Each caller would `scripts/bootstrap-workspace.sh <args>` instead of sourcing functions.

**Pros:**
- Even stronger isolation — no shared shell process, no risk of variable leakage

**Cons:**
- Subprocess overhead and more awkward error propagation (exit codes only, no shared function return values) for a sequence that legitimately needs to report partial-failure state (e.g. tolerate a failed `l5-swagger:generate`) back to the caller
- Passing complex per-step config across a process boundary is clumsier than a function call

---

## Consequences

**Positive:**
- `./scripts/setup.sh --workspaces=N` and `./scripts/create-workspace.sh` now produce byte-identical `.env`/`Procfile.dev` output through the same code path — verified by diffing generated files against pre-refactor output
- `init.sh` no longer carries its own copy of the `Procfile.dev` template

**Negative / trade-offs:**
- One intentional behavior unification: `bootstrap_laravel()` now tolerates a failed `l5-swagger:generate` (warns, continues) in `create-workspace.sh`'s fresh-clone path, matching the tolerance `setup.sh` already had. Previously `create-workspace.sh` alone aborted on that failure — this is a deliberate behavior change, not a regression.

**Neutral:**
- `scripts/lib/` is now an established location for shared script logic; future cross-script duplication should be extracted there too

---

## Requirements Addressed

| ID | Description | Type |
|----|-------------|------|
| — | `setup.sh`, `create-workspace.sh`, and `init.sh` must produce identical workspace bootstrap output for the same inputs | Functional |
| — | The `Procfile.dev` template must exist in exactly one place in the repository | Non-functional |
| — | A future change to the bootstrap sequence must require editing exactly one file | Non-functional |
| — | `shellcheck scripts/*.sh scripts/lib/*.sh` must pass with no errors | Non-functional |

---

## Links

- Related issue: [#10 — Extract shared workspace bootstrap logic to eliminate duplication](https://github.com/pakodiazdev/sushigo-dev-lab/issues/10)
- Implemented in PR: [#62](https://github.com/pakodiazdev/sushigo-dev-lab/pull/62)
- Related ADR: [ADR-003 — Safe workspace deletion ordering](003-safe-workspace-deletion.md)
