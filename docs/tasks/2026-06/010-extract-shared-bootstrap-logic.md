# 010 - Chore: Extract Shared Workspace Bootstrap Logic to Eliminate Duplication

**Type:** 🔨 Refactor  
**Priority:** Medium  
**GitHub Issue:** [#10](https://github.com/pakodiazdev/sushigo-dev-lab/issues/10)  
**Related repo:** pakodiazdev/sushigo-dev-lab only

---

## 📖 Story

**English:**  
As a maintainer of the dev-lab, I need the workspace bootstrap logic to live in one place so that adding a new artisan command, changing a `.env` key, or updating the Procfile template only requires editing one file.

**Español:**  
Como mantenedor del dev-lab, necesito que la lógica de bootstrap del workspace viva en un solo lugar para que agregar un nuevo comando artisan, cambiar una clave de `.env`, o actualizar el template de Procfile solo requiera editar un archivo.

---

## 🧩 Context

`scripts/setup.sh` and `scripts/create-workspace.sh` share approximately 100 lines of identical code. The `Procfile.dev` template alone appears in three locations:

- `setup.sh` lines 152 and 217
- `create-workspace.sh` line 146
- `init.sh` — `write_procfile()` function

Every time the bootstrap sequence changes (new artisan command, new env key, new dev flag), both `setup.sh` and `create-workspace.sh` must be updated in sync. This has already drifted once — `write_procfile` was added to `init.sh` but the same logic remains hardcoded in the other two scripts.

---

## ✅ Technical Tasks

- [ ] 🔨 Create `scripts/lib/workspace-bootstrap.sh` as a sourced library
- [ ] 🔨 Extract `configure_api_env()` — all `sed -i ''` calls for `code/api/.env`
- [ ] 🔨 Extract `configure_webapp_env()` — writes `code/webapp/.env`
- [ ] 🔨 Extract `configure_workspace_env()` — writes workspace root `.env`
- [ ] 🔨 Extract `write_procfile()` — single source of truth for Procfile template (remove from `init.sh` too, source from lib)
- [ ] 🔨 Extract `install_deps()` — `composer install` + `npm install`
- [ ] 🔨 Extract `bootstrap_laravel()` — `key:generate`, `passport:keys`, `migrate`, `db:seed`, `l5-swagger:generate`
- [ ] 🔨 Update `setup.sh` to source lib and call functions instead of inline code
- [ ] 🔨 Update `create-workspace.sh` to source lib and call functions
- [ ] 🔨 Update `init.sh` to source lib for `write_procfile`
- [ ] ✅ Run `shellcheck scripts/*.sh scripts/lib/*.sh` — no errors
- [ ] ✅ Test `./scripts/setup.sh --workspaces=2` end-to-end — identical result to today
- [ ] ✅ Test `./scripts/create-workspace.sh` — identical result to today

---

## 🎯 Acceptance Criteria

- [ ] `scripts/lib/workspace-bootstrap.sh` exists and is sourced by all three scripts
- [ ] The `Procfile.dev` template exists in exactly one place
- [ ] A change to the bootstrap sequence requires editing exactly one file
- [ ] No behavior regression in any script
- [ ] `shellcheck` passes on all scripts including the new lib

---

## 🔗 References

- `scripts/setup.sh:169-261` — duplicated bootstrap block
- `scripts/create-workspace.sh:98-185` — same duplicated block
- `scripts/init.sh:41-47` — `write_procfile()` that already exists in isolation
- GitHub Issue: [pakodiazdev/sushigo-dev-lab #10](https://github.com/pakodiazdev/sushigo-dev-lab/issues/10)

---

## ⏱️ Estimates

- **Optimistic:** `2h`
- **Pessimistic:** `4h`
- **Status:** 🔲 Backlog
