# 013 - Chore: Resolve Two Dead Configuration Items

**Type:** 🔧 Chore  
**Priority:** Low  
**GitHub Issue:** [#13](https://github.com/pakodiazdev/sushigo-dev-lab/issues/13)  
**Related repo:** pakodiazdev/sushigo-dev-lab only

---

## 📖 Story

**English:**  
As a developer reading the repo config files, I need every configuration value to either do what its name implies or be clearly documented as intentional, so I don't waste time investigating variables that have no runtime effect.

**Español:**  
Como desarrollador leyendo los archivos de configuración del repo, necesito que cada valor de configuración haga lo que su nombre implica o esté claramente documentado como intencional, para no perder tiempo investigando variables que no tienen efecto en runtime.

---

## 🧩 Context

Two configuration items exist that either do nothing or behave differently than a developer would expect:

### Item 1 — `sushigo_shared` database in `docker-compose.yml`

`POSTGRES_DB: sushigo_shared` creates a database on every `docker compose up`. No script in this repo connects to it. Each workspace uses `sushigo_ws_<letter>`. The default could be `postgres` (always exists, no unused DB created).

### Item 2 — `AGENT_LABEL_*` in `tools.env` is silently ignored at runtime

`tools.env.example` documents per-slot label overrides (`AGENT_LABEL_A=[Alpha]`). These values are written to `code/webapp/.env` only once at workspace creation. On every subsequent `./scripts/init.sh`, `inject_agent_label()` recalculates the label from the current git branch — completely ignoring what is in `tools.env`. A developer who customizes their label will see it reset on every restart with no explanation.

---

## ✅ Technical Tasks

### `sushigo_shared` database

- [ ] 🔧 Decide: intentional (for manual inspection) OR dead config
  - If intentional: add comment to `docker-compose.yml` explaining its purpose
  - If dead: change `POSTGRES_DB` to `postgres` and remove the unused database creation

### `AGENT_LABEL_*` runtime discrepancy

- [ ] 🔧 Option A — Make `inject_agent_label()` read from `tools.env`: load `AGENT_LABEL_<LETTER>` as the base label before appending the issue number (instead of hardcoding `[${letter}]`)
- [ ] 🔧 Option B — Document as setup-only: add a comment to `tools.env.example` clearly stating `AGENT_LABEL_*` is only applied during initial workspace creation and has no effect on `init.sh` restarts
- [ ] 📝 Update `tools.env.example` comments to accurately reflect when each variable takes effect

---

## 🎯 Acceptance Criteria

- [ ] `docker-compose.yml` either has a comment explaining `sushigo_shared` or it no longer creates an unused database
- [ ] `AGENT_LABEL_*` in `tools.env` is either respected at runtime OR documented as setup-only with a clear comment
- [ ] `tools.env.example` comments are accurate and trustworthy
- [ ] No behavior regression in workspace startup

---

## 🔗 References

- `docker-compose.yml:7` — `POSTGRES_DB: sushigo_shared`
- `tools.env.example:39-47` — `AGENT_LABEL_*` configuration
- `scripts/init.sh:56-77` — `inject_agent_label()` that ignores `tools.env`
- `scripts/setup.sh:103-105` — where `AGENT_LABEL_*` is actually read (only at setup time)
- GitHub Issue: [pakodiazdev/sushigo-dev-lab #13](https://github.com/pakodiazdev/sushigo-dev-lab/issues/13)

---

## ⏱️ Estimates

- **Optimistic:** `30m`
- **Pessimistic:** `1h`
- **Status:** 🔲 Backlog
