# ADR-001: Dynamic workspace identity label injected by init.sh

> **Status:** Accepted  
> **Date:** 2026-06-03  
> **Deciders:** pakodiazdev

---

## Context

`sushigo-dev-lab` runs up to 8 simultaneous workspaces (`sushigo-a` through `sushigo-h`), each on a different git branch. During multi-agent development the developer has multiple browser tabs, terminals, and editor windows open at the same time — one per workspace.

Without a visual identity in the UI, it is easy to confuse which browser tab corresponds to which workspace and which issue is being worked on. A static label set once at `setup.sh` time shows the slot letter (`[A]`) but becomes stale the moment the developer switches branches.

The label needs to be accurate at every startup, without requiring any manual `.env` edits from the developer.

---

## Decision

`init.sh` reads the current git branch of each workspace on every startup and injects the agent label into `code/webapp/.env`:

- `VITE_AGENT_LABEL` — slot letter + issue number extracted from branch name (e.g. `[A:#065]`)

`VITE_AGENT_LABEL` is used by `index.html` as the browser tab title prefix.  
The full git branch name is shown in the DevDebugger panel via the `virtual:git-branch` Vite plugin (see Option 3 below), which reads `.git/HEAD` live and triggers an HMR reload on `git checkout` — no dev server restart needed.

> **Update (2026-06-04):** `VITE_GIT_BRANCH` was originally injected by `init.sh` as a static env var. It was superseded by a runtime Vite virtual module (`virtual:git-branch`) that watches `.git/HEAD` and updates the DevDebugger label on every `git checkout` without restarting the dev server. `init.sh` no longer writes `VITE_GIT_BRANCH`.

---

## Considered Options

### Option 1: Static label set once by `setup.sh`

Set `VITE_AGENT_LABEL=[A]` in `.env` during workspace creation and never update it.

**Pros:**
- Simple — no extra logic in `init.sh`

**Cons:**
- Becomes stale immediately after the developer switches branches
- Shows no issue number — the most useful context is missing
- Developer must manually edit `.env` to keep it meaningful

---

### Option 2: Dynamic label injected by `init.sh` on every startup ✅ *(chosen)*

`init.sh` runs `git rev-parse --abbrev-ref HEAD` on each workspace directory, extracts the issue number with `grep -oE '[0-9]+ | head -1`, and rebuilds the label before starting Overmind.

**Pros:**
- Always accurate — reflects the actual branch at startup time
- Issue number visible in the tab title without opening a terminal
- Zero manual steps — the developer just runs `init.sh`
- Falls back gracefully to `[A]` if no issue number is found in the branch name

**Cons:**
- Adds a git subprocess call to `init.sh` startup
- Label is only updated at startup — mid-session branch switches require a restart (acceptable)

---

### Option 3: Read git branch at runtime via Vite virtual module ✅ *(chosen for DevDebugger)*

A custom Vite plugin exposes `virtual:git-branch` — reads `git rev-parse --abbrev-ref HEAD` at load time and watches `.git/HEAD` for changes. On `git checkout`, Vite invalidates the module and emits a full HMR reload.

**Pros:**
- Updates without restarting the dev server
- No env var to inject or keep in sync
- Browser reflects the actual branch at all times during a session

**Cons:**
- Requires a custom Vite plugin in `vite.config.ts`
- Couples the frontend build tool to a shell dependency (`git`)

> Implemented in [pakodiazdev/sushigo#161](https://github.com/pakodiazdev/sushigo/pull/161).

---

## Consequences

**Positive:**
- Developer always knows which workspace/issue they are looking at, at a glance
- Eliminates workspace confusion errors during multi-agent parallel development
- No manual steps — consistent with the lab's "zero manual config" philosophy

**Negative / trade-offs:**
- Label reflects the branch at startup time, not live — a branch switch mid-session requires restarting `init.sh` to update `VITE_AGENT_LABEL` (tab title). The DevDebugger branch label updates live via the Vite plugin.
- `VITE_AGENT_LABEL` value in `.env` is transient — it should not be committed

**Neutral:**
- `tools.env` and `tools.env.example` gained `AGENT_LABEL_A..H` entries as the base label source per slot

---

## Requirements Addressed

| ID | Description | Type |
|----|-------------|------|
| — | Browser tab must identify the active workspace slot and current issue being worked on | Functional |
| — | DevDebugger panel must show the full git branch name for orientation in multi-branch sessions | Functional |
| — | Branch label in DevDebugger must update on `git checkout` without restarting the dev server | Functional |
| — | Workspace label must update automatically on every `init.sh` run without manual `.env` edits | Non-functional |
| — | Fallback must work gracefully when branch name contains no issue number | Non-functional |

---

## Links

- Related issue (dev-lab): [#003 — Add dynamic workspace identity label system with ADR documentation](https://github.com/pakodiazdev/sushigo-dev-lab/issues/3)
- Related issue (sushigo): [#159 — Add dynamic workspace label to DevDebugger panel and vite-env types](https://github.com/pakodiazdev/sushigo/issues/159)
- Implemented in PR: *(pending)*
- Related ADR: *(none)*
