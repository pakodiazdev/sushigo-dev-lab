# 009 - Bug: init.sh Shorthand Workspace Name Routes to Non-Existent Directory

**Type:** 🐛 Bug Fix  
**Priority:** High  
**GitHub Issue:** [#9](https://github.com/pakodiazdev/sushigo-dev-lab/issues/9)  
**Related repo:** pakodiazdev/sushigo-dev-lab only

---

## 📖 Story

**English:**  
As a developer running a single workspace, I need `./scripts/init.sh a` to resolve to `sushigo-a` so I can use shorthand names without getting a "workspace not found" error.

**Español:**  
Como desarrollador arrancando un workspace, necesito que `./scripts/init.sh a` resuelva a `sushigo-a` para poder usar nombres cortos sin obtener un error de "workspace not found".

---

## 🧩 Context

The name normalization block in `scripts/init.sh:97-101` was written when workspaces were called `agent-a`. The naming convention later changed to `sushigo-a`, but this block was never updated. The comment still references the old pattern.

**What happens today:**
```
./scripts/init.sh a
  TARGET = "a"
  → "agent-a"       (first if block)
  → "sushigo-agent-a"  (second if block)
  → ❌ Workspace not found: sushigo-agent-a
```

`reset-workspace-db.sh` handles shorthand correctly and serves as the reference implementation.

---

## ✅ Technical Tasks

- [ ] 🐛 Replace the two-step normalization in `init.sh:97-101` with the same pattern used in `reset-workspace-db.sh`: strip `sushigo-` prefix → validate single letter `a–h` → reconstruct as `sushigo-<letter>`
- [ ] 🐛 Remove or update the stale comment `# Accept "a", "agent-a", or "sushigo-agent-a"` to reflect the current naming convention
- [ ] ✅ Test: `./scripts/init.sh a` → starts `sushigo-a` (foreground)
- [ ] ✅ Test: `./scripts/init.sh sushigo-a` → no regression
- [ ] ✅ Test: `./scripts/init.sh z` → clear error message
- [ ] ✅ Run `shellcheck scripts/init.sh` — no errors

---

## 🎯 Acceptance Criteria

- [ ] `./scripts/init.sh a` starts `workspaces/sushigo-a` correctly
- [ ] `./scripts/init.sh sushigo-a` still works (no regression)
- [ ] Invalid input exits with a descriptive error and lists available workspaces
- [ ] Normalization logic is consistent with `reset-workspace-db.sh`

---

## 🔗 References

- `scripts/init.sh:97-101` — broken normalization block
- `scripts/reset-workspace-db.sh:31-34` — correct reference implementation
- GitHub Issue: [pakodiazdev/sushigo-dev-lab #9](https://github.com/pakodiazdev/sushigo-dev-lab/issues/9)

---

## ⏱️ Estimates

- **Optimistic:** `30m`
- **Pessimistic:** `1h`
- **Status:** 🔲 Backlog
