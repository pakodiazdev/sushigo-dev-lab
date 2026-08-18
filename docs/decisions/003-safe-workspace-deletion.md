# ADR-003: Safe, ordered workspace deletion via delete-workspace.sh

> **Status:** Accepted
> **Date:** 2026-07-25
> **Deciders:** pakodiazdev

---

## Context

`create-workspace.sh` could add a workspace slot, but there was no corresponding way to remove one. Reclaiming a slot required three manual steps: stopping Overmind by hand from inside the workspace directory, dropping the database directly via `psql`, and `rm -rf`-ing the workspace directory. With up to 8 slots and one workspace per feature branch, slot reclamation was expected to be a frequent operation, and the manual sequence was error-prone — most notably, it was easy to drop a database while Overmind (or, once #16 shipped, the E2E stack) still held active connections to it, and easy to forget the `_test`/`_e2e` databases entirely and only drop the primary one.

---

## Decision

Add `scripts/delete-workspace.sh <workspace>`, accepting both `sushigo-a` and shorthand `a` (same normalization as `reset-workspace-db.sh`). It validates the workspace exists, then executes a strict teardown order: stop the workspace's Overmind session (socket detection, same pattern as `make down`) → stop its E2E stack via `stop-e2e.sh` → terminate active connections and drop all three per-workspace databases (`sushigo_ws_<letter>`, `_test`, `_e2e`) → remove `workspaces/sushigo-<letter>`. It never touches shared Docker services or other workspaces, and exits with a clear error — listing available workspaces — instead of silently no-op'ing on an invalid or missing target.

---

## Considered Options

### Option 1: Document the manual three-step sequence instead of scripting it

**Pros:**
- Zero implementation cost

**Cons:**
- Already the status quo, and already proven error-prone (connection-drop ordering mistakes, forgotten `_test`/`_e2e` databases)
- Every deletion requires remembering the shared-services host/port/credentials by hand

---

### Option 2: Single script, strict ordered teardown ✅ *(chosen)*

**Pros:**
- One command replaces three manual, ordering-sensitive steps
- `pg_terminate_backend` before `DROP DATABASE` removes the most common manual-deletion failure (drop fails or hangs because Overmind/E2E still holds a connection)
- Stopping the E2E stack before dropping `_e2e` specifically prevents the e2e-api container from reconnecting between the terminate and the drop — a race the manual process had no defense against
- Fails loudly and lists available workspaces on a bad target, instead of silently doing nothing

**Cons:**
- Couples this script to `stop-e2e.sh`'s existence and behavior (see [ADR-004](004-per-slot-e2e-infrastructure.md)) — deleting a workspace before #16 shipped would have needed a smaller version of this script without the E2E step

---

### Option 3: Fold deletion into `create-workspace.sh` as a `--delete` flag

**Pros:**
- One fewer script file

**Cons:**
- Conflates two unrelated operations (add vs. remove a slot) behind one entrypoint and flag-parsing branch
- Breaks the existing pattern where each lifecycle operation (`create-workspace.sh`, `reset-workspace-db.sh`) is its own script with its own `Makefile` target

---

## Consequences

**Positive:**
- Slot reclamation is now a single command: `./scripts/delete-workspace.sh sushigo-a` or `make delete-workspace WORKSPACE=sushigo-a`
- All three per-workspace databases are dropped together — no more orphaned `_test`/`_e2e` databases left behind by manual cleanup
- Connection-termination-before-drop ordering removes the most common manual failure mode

**Negative / trade-offs:**
- The script assumes `stop-e2e.sh` exists and is safe to call even when no E2E stack is running for that slot (it is — `stop-e2e.sh` no-ops cleanly in that case)

**Neutral:**
- `docs/troubleshooting.md`'s manual "remove all workspaces" recipe (which only covered slots `a`–`d` and never dropped `_test`/`_e2e`) was replaced with a reference to this script

---

## Requirements Addressed

| ID | Description | Type |
|----|-------------|------|
| — | `delete-workspace.sh <workspace>` must remove the workspace directory and drop all of its databases (primary, test, e2e) | Functional |
| — | Shorthand letter form (`a`) must be accepted, matching `reset-workspace-db.sh` | Functional |
| — | Active database connections must be terminated before the database is dropped | Functional |
| — | Running against a non-existent workspace must exit with a clear error, not a silent no-op | Non-functional |
| — | Other workspaces and shared Docker services must be unaffected | Non-functional |

---

## Links

- Related issue: [#11 — Add delete-workspace.sh to cleanly remove a workspace slot](https://github.com/pakodiazdev/sushigo-dev-lab/issues/11)
- Implemented in PR: [#61](https://github.com/pakodiazdev/sushigo-dev-lab/pull/61)
- Related ADR: [ADR-002 — Shared workspace-bootstrap library](002-shared-workspace-bootstrap-library.md), [ADR-004 — Per-slot E2E infrastructure](004-per-slot-e2e-infrastructure.md)
