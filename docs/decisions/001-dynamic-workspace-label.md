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

`init.sh` reads the current git branch of each workspace on every startup and injects two variables into `code/webapp/.env`:

- `VITE_AGENT_LABEL` — slot letter + issue number extracted from branch name (e.g. `[A:#065]`)
- `VITE_GIT_BRANCH` — full branch name (e.g. `feature/065-dynamic-label`)

`VITE_AGENT_LABEL` is used by `index.html` as the browser tab title prefix.  
`VITE_GIT_BRANCH` is shown in the DevDebugger panel header.

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

### Option 3: Read git branch at runtime from the browser (JavaScript)

Use a custom Vite plugin or a dev-server middleware to expose `git rev-parse` output as an env variable at HMR time.

**Pros:**
- Updates without restarting the dev server

**Cons:**
- Requires a custom Vite plugin — significant added complexity
- Couples the frontend build tool to a shell dependency
- Overkill: branch switches during an active dev session are uncommon

---

## Consequences

**Positive:**
- Developer always knows which workspace/issue they are looking at, at a glance
- Eliminates workspace confusion errors during multi-agent parallel development
- No manual steps — consistent with the lab's "zero manual config" philosophy

**Negative / trade-offs:**
- Label reflects the branch at startup time, not live — a branch switch mid-session requires restarting `init.sh` to update the label
- `VITE_AGENT_LABEL` and `VITE_GIT_BRANCH` values in `.env` are transient — they should not be committed

**Neutral:**
- `tools.env` and `tools.env.example` gained `AGENT_LABEL_A..H` entries as the base label source per slot

---

## Requirements Addressed

| ID | Description | Type |
|----|-------------|------|
| — | Browser tab must identify the active workspace slot and current issue being worked on | Functional |
| — | DevDebugger panel must show the full git branch name for orientation in multi-branch sessions | Functional |
| — | Workspace label must update automatically on every `init.sh` run without manual `.env` edits | Non-functional |
| — | Fallback must work gracefully when branch name contains no issue number | Non-functional |

---

## Links

- Related issue (dev-lab): [#003 — Add dynamic workspace identity label system with ADR documentation](https://github.com/pakodiazdev/sushigo-dev-lab/issues/3)
- Related issue (sushigo): [#159 — Add dynamic workspace label to DevDebugger panel and vite-env types](https://github.com/pakodiazdev/sushigo/issues/159)
- Implemented in PR: *(pending)*
- Related ADR: *(none)*
