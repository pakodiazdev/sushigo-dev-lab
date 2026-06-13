# 012 - Docs: Update architecture.md Startup Flow — init-agent-workspace.sh No Longer Used

**Type:** 📚 Documentation  
**Priority:** Low  
**GitHub Issue:** [#12](https://github.com/pakodiazdev/sushigo-dev-lab/issues/12)  
**Related repo:** pakodiazdev/sushigo-dev-lab only

---

## 📖 Story

**English:**  
As a developer reading the architecture docs to understand how workspaces start, I need the startup flow diagram to reflect what `init.sh` actually does so I can debug process issues without chasing a script that is never called.

**Español:**  
Como desarrollador leyendo la documentación de arquitectura para entender cómo arrancan los workspaces, necesito que el diagrama del flujo de inicio refleje lo que `init.sh` realmente hace para poder depurar problemas de procesos sin buscar un script que nunca se llama.

---

## 🧩 Context

`docs/architecture.md` shows a startup flow that has been outdated since `init.sh` was refactored to call Overmind directly:

**Current diagram (stale):**
```
make init WORKSPACE=sushigo-a
  └── scripts/init.sh sushigo-a
        └── bash init-agent-workspace.sh
              └── source .env
              └── overmind start -f Procfile.dev
```

**Actual flow (single workspace):**
```
make init WORKSPACE=sushigo-a
  └── scripts/init.sh sushigo-a
        └── inject_agent_label()      — updates VITE_AGENT_LABEL in webapp .env
        └── source workspaces/sushigo-a/.env
        └── write_procfile()          — regenerates Procfile.dev
        └── exec overmind start -f Procfile.dev
```

`init-agent-workspace.sh` exists in the sushigo repo but is never invoked by `init.sh`. The bypass is intentional: single-workspace mode needs foreground output; multi-workspace mode needs daemon `-D` mode. Neither maps cleanly to the sushigo boot script.

The Component responsibilities table also partially misrepresents this.

---

## ✅ Technical Tasks

- [ ] 📝 Replace the startup flow diagram with the accurate single-workspace sequence
- [ ] 📝 Add the all-workspaces (background) flow as a second diagram
- [ ] 📝 Add a brief explanation of *why* `init-agent-workspace.sh` is bypassed (foreground vs daemon requirement)
- [ ] 📝 Update the Component responsibilities table — clarify that `init-agent-workspace.sh` exists in sushigo but is not invoked by the dev-lab's `init.sh`
- [ ] ✅ Cross-check: no other references in `docs/` point to a flow that no longer exists

---

## 🎯 Acceptance Criteria

- [ ] The startup flow diagram in `docs/architecture.md` matches what `scripts/init.sh` actually does
- [ ] Both single-workspace and all-workspaces flows are documented
- [ ] The reason `init-agent-workspace.sh` is bypassed is explained
- [ ] Component responsibilities table is accurate
- [ ] No stale references remain in any file under `docs/`

---

## 🔗 References

- `docs/architecture.md:76-85` — stale startup flow diagram
- `docs/architecture.md:24-28` — Component responsibilities table
- `scripts/init.sh:94-121` — actual single-workspace startup implementation
- `scripts/init.sh:141-183` — actual all-workspaces background implementation
- GitHub Issue: [pakodiazdev/sushigo-dev-lab #12](https://github.com/pakodiazdev/sushigo-dev-lab/issues/12)

---

## ⏱️ Estimates

- **Optimistic:** `30m`
- **Pessimistic:** `1h`
- **Status:** 🔲 Backlog
