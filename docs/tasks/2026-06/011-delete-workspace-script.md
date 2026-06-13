# 011 - Feature: Add delete-workspace.sh to Cleanly Remove a Workspace Slot

**Type:** ✨ Feature  
**Priority:** Medium  
**GitHub Issue:** [#11](https://github.com/pakodiazdev/sushigo-dev-lab/issues/11)  
**Related repo:** pakodiazdev/sushigo-dev-lab only

---

## 📖 Story

**English:**  
As a developer who regularly creates workspaces per feature branch, I need a single command to cleanly remove a workspace — stopping its processes, dropping its database, and freeing its slot — so I can reclaim disk space and reuse slot letters without manual steps.

**Español:**  
Como desarrollador que crea workspaces por feature branch regularmente, necesito un comando único para eliminar un workspace de forma limpia — deteniendo sus procesos, eliminando su base de datos y liberando su slot — para poder recuperar espacio en disco y reutilizar letras de slot sin pasos manuales.

---

## 🧩 Context

`create-workspace.sh` exists but has no inverse. Removing a workspace today requires three manual steps that are easy to get wrong — especially forgetting to terminate active DB connections before the drop, which causes `dropdb` to fail silently or with a confusing error.

With up to 8 slots and one workspace per feature branch, slot reclamation is a frequent operation. The missing script creates a UX gap in the lifecycle management of workspaces.

---

## ✅ Technical Tasks

- [ ] ✨ Create `scripts/delete-workspace.sh`
- [ ] ✨ Accept `sushigo-a` or shorthand `a` (same normalization as `reset-workspace-db.sh`)
- [ ] ✨ Validate: workspace directory exists — exit with error if not found, list available workspaces
- [ ] ✨ Stop Overmind: detect `.overmind.sock` in workspace dir → run `overmind quit` if present
- [ ] ✨ Terminate active DB connections via `pg_terminate_backend` before drop
- [ ] ✨ Drop the workspace database (`DROP DATABASE IF EXISTS sushigo_ws_<letter>`)
- [ ] ✨ `rm -rf workspaces/sushigo-<letter>`
- [ ] ✨ Print confirmation summary (workspace removed, database dropped, slot freed)
- [ ] ✨ Add `delete-workspace` target to `Makefile` (with `WORKSPACE` guard matching `reset-db`)
- [ ] 📝 Add `make delete-workspace WORKSPACE=sushigo-a` to `make help` output
- [ ] 📝 Document usage in `docs/workspaces.md` under a new "Deleting workspaces" section
- [ ] ✅ Run `shellcheck scripts/delete-workspace.sh` — no errors
- [ ] ✅ Test: removes workspace dir and database, does not affect other workspaces
- [ ] ✅ Test: graceful error when workspace does not exist

---

## 🎯 Acceptance Criteria

- [ ] `./scripts/delete-workspace.sh sushigo-a` removes directory and drops database
- [ ] Shorthand `./scripts/delete-workspace.sh a` works
- [ ] Running on a non-existent workspace exits with a clear error (no silent no-op)
- [ ] Active DB connections are terminated before the drop
- [ ] Overmind session is stopped if running
- [ ] Other workspaces are completely unaffected
- [ ] `make delete-workspace WORKSPACE=sushigo-a` works and is in `make help`
- [ ] Documented in `docs/workspaces.md`
- [ ] `shellcheck` passes

---

## 🔗 References

- `scripts/create-workspace.sh` — the inverse operation this script complements
- `scripts/reset-workspace-db.sh` — reference for normalization pattern and DB operations
- `Makefile:66-70` — `reset-db` target as model for the new `delete-workspace` target
- GitHub Issue: [pakodiazdev/sushigo-dev-lab #11](https://github.com/pakodiazdev/sushigo-dev-lab/issues/11)

---

## ⏱️ Estimates

- **Optimistic:** `1h`
- **Pessimistic:** `2h`
- **Status:** 🔲 Backlog
