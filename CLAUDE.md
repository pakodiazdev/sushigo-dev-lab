# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**sushigo-dev-lab** is the multi-agent local development environment for [SushiGo](https://github.com/pakodiazdev/sushigo) — a full-stack tenant platform built with Laravel 12 + React 19.

This repo contains:
- **Shared Docker services** (`docker-compose.yml`) — PostgreSQL, Redis, Mailpit
- **Orchestration scripts** (`scripts/`) — setup, init, create-workspace, reset-db
- **Documentation** (`docs/`) — architecture decisions, agent workflows, troubleshooting

This repo does NOT run Laravel or Vite directly. Those live inside each agent clone (subdirectories under `agents/`, which are gitignored). The startup logic lives in `sushigo` itself (`init-agent-workspace.sh` + `Procfile.dev`).

## Language Rule

**All code, documentation, commit messages, and task files in this repository are in English.**  
The only exception is UI text — but this repo has no UI, so everything is English.

This applies to: script comments, README, docs/, CLAUDE.md, variable names, error messages.

## Repository Structure

```
sushigo-dev-lab/
├── docker-compose.yml          ← shared infrastructure services
├── .gitignore                  ← workspaces/ is excluded here
├── Makefile                    ← developer shortcuts
├── scripts/
│   ├── setup.sh                ← initialize N workspaces from scratch
│   ├── create-workspace.sh     ← add one more workspace at any time
│   ├── init.sh                 ← start one or all workspaces
│   └── reset-workspace-db.sh   ← wipe + remigrate one workspace's DB
├── docs/
│   ├── architecture.md
│   ├── workspaces.md
│   └── troubleshooting.md
├── workspaces/                 ← gitignored — created by setup.sh
└── README.md
```

## Development Commands

```bash
# Start shared Docker services
docker compose up -d

# Stop shared services
docker compose down

# Initialize the lab (3 workspaces)
./scripts/setup.sh --workspaces=3

# Start a specific workspace
./scripts/init.sh sushigo-a

# Start all workspaces
./scripts/init.sh

# Add a new workspace
./scripts/create-workspace.sh

# Reset one workspace's database
./scripts/reset-workspace-db.sh sushigo-a

# Makefile shortcuts
make up
make down
make init WORKSPACE=sushigo-a
make reset-db WORKSPACE=sushigo-a
```

## Conventions

### Pre-commit Checks (mandatory)

This repo contains shell scripts (`.sh`) and YAML/Markdown files. Before committing:

```bash
# Validate shell scripts (install: brew install shellcheck)
shellcheck scripts/*.sh

# Validate docker-compose
docker compose config --quiet
```

**Rules:**
- All shell scripts must pass `shellcheck` with no errors
- `docker-compose.yml` must pass `docker compose config --quiet`
- Never commit with shellcheck errors

---

### Commit Messages (mandatory — always follow this exactly)

**Why this format exists:**

- **Issue number `[#NNN]`** — every commit must link to a GitHub issue. The issue is where the full context lives: *why* the change was needed, *what problem* it solves, *what decision* was made and why. Without it, future maintainers see code in a state they can't explain. A commit with no issue number is a hard blocker.
- **Emojis instead of words** — `✨` replaces `feat`, `🐛` replaces `fix`, `🔨` replaces `refactor`. One character carries the same semantic weight as a whole word, keeps the subject line scannable at a glance, and makes the category immediately visible in `git log` without reading. Each emoji has a fixed meaning — they are not decoration, they are the category label.

**Format — every field is required:**

```
:emoji [#NNN] - short description :emoji

- :emoji Activity 1
- :emoji Activity 2
- :emoji Activity 3
```

**Rules:**
- **Every commit MUST be tied to a GitHub issue number** — no commit without `[#NNN]`
- Subject line: `emoji [#NNN] - description emoji` — the dash (` - `) between issue and description is mandatory
- Each bullet in the body **must start with an emoji** — plain `- text` is not allowed
- Issue number is always 3 digits zero-padded: `#001`, `#030`, not `#1` or `#30`
- Description is concise (imperative mood), never a sentence ending in a period
- Final ornamental emoji on the subject line is required
- Reuse the issue number across commits if they belong to the same task

**Emoji types:**

| Emoji | Type | When to use |
|---|---|---|
| ✨ | feat | new script or feature |
| 🐛 | fix | bug fix in a script |
| 📚 | docs | README, docs/, comments |
| 🎨 | style | formatting, no logic change |
| 🔨 | refactor | code restructure |
| 🚀 | perf | performance improvement |
| ✅ | test | adding/updating tests |
| 🔧 | chore | config, tooling, maintenance |

**Correct example:**

```
🔧 [#001] - Add docker-compose with shared PostgreSQL, Redis and Mailpit 🐳

- 🐳 Added PostgreSQL 16 with persistent volume
- 📬 Added Mailpit for email capture
- 🔄 Added Redis 7-alpine for cache/queues
- 📝 Added .env.example with required vars
```

**Wrong (do not do this):**

```
🔧 [#001] Add docker-compose              ← missing dash after issue number
- Added PostgreSQL                         ← missing emoji on bullet
- Added Redis                              ← missing emoji on bullet

chore: add docker-compose                  ← no issue, word instead of emoji
fix: update script                         ← no issue, no emoji body
```

---

### Branch Naming (mandatory)

```
<type>/<NNN>-<short-description>
```

| Type | Emoji | When |
|---|---|---|
| `feature/` | ✨ | new script, new functionality |
| `fix/` | 🐛 | bug fix |
| `refactor/` | 🔨 | restructure without behavior change |
| `docs/` | 📚 | documentation only |
| `chore/` | 🔧 | config, tooling |

**Rules:**
- Lowercase, kebab-case only
- Issue number zero-padded to 3 digits
- 2–5 word description, English only
- Always branch from `main`

**Examples:**
```
feature/001-setup-script
feature/002-init-script
fix/003-postgres-health-check
docs/004-troubleshooting-guide
```

---

### Script Style (mandatory for all `.sh` files)

```bash
#!/bin/bash
set -euo pipefail   # exit on error, undefined vars, pipe failures
```

**Rules:**
- Always start with `set -euo pipefail` — prevents silent failures
- Validate required arguments at the top and exit with usage message if missing
- Use `echo "✅ Done"` / `echo "❌ Error: ..."` for user-facing output — consistent with README examples
- Quote all variable expansions: `"$VAR"` not `$VAR`
- Use `command -v tool &>/dev/null` for prerequisite checks, not `which`
- Functions use `snake_case`
- No hardcoded credentials — read from `.env` or environment variables

**Example:**

```bash
#!/bin/bash
set -euo pipefail

AGENT="${1:-}"

if [ -z "$AGENT" ]; then
  echo "Usage: $0 <agent-name>"
  echo "Example: $0 agent-a"
  exit 1
fi

if ! command -v overmind &>/dev/null; then
  echo "❌ Overmind not found. Install with: brew install overmind"
  exit 1
fi
```

---

### Documentation Style

- All docs in `docs/` are Markdown, English only
- Use tables for comparisons, port assignments, and command references
- Use code blocks with language hints (` ```bash `, ` ```yaml `)
- Keep the README quickstart under 10 commands — it must stay scannable
- `troubleshooting.md` entries follow this structure:
  ```
  ### ❌ Error message or symptom
  **Cause:** one line
  **Fix:**
  ```bash
  command to fix it
  ```
  ```

---

### What NOT to commit

- `agents/` directory or any files inside it
- `.env` files (only `.env.example`)
- Editor config (`.vscode/`, `.idea/`) — use global gitignore
- OS files (`.DS_Store`, `Thumbs.db`)

---

## Related Repositories

| Repo | Purpose |
|---|---|
| [pakodiazdev/sushigo](https://github.com/pakodiazdev/sushigo) | Main SushiGo monorepo (Laravel API + React webapp) |
| [pakodiazdev/sushigo-dev-lab](https://github.com/pakodiazdev/sushigo-dev-lab) | This repo — orchestration layer |

The `init-agent-workspace.sh` and `Procfile.dev` that each agent uses live in `pakodiazdev/sushigo`, not here. Changes to those files require a PR to the sushigo repo.

## Key Files

- `docker-compose.yml` — shared services definition
- `scripts/setup.sh` — full lab initialization
- `scripts/init.sh` — workspace startup orchestrator
- `Makefile` — developer shortcuts
- `docs/architecture.md` — design decisions and rationale
- `docs/troubleshooting.md` — common errors and fixes
