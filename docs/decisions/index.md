# Technical Decisions

This index lists all Architecture Decision Records (ADRs) for `sushigo-dev-lab`.

Each ADR captures a significant technical decision: what was decided, why, what alternatives were considered, and what requirements it addresses.

> **New decision?** Copy [000-template.md](000-template.md), name it `NNN-short-title.md` (zero-padded), and add a row to this table.

---

## Decision log

| ADR | Title | Status | Date |
|-----|-------|--------|------|
| [ADR-001](001-dynamic-workspace-label.md) | Dynamic workspace identity label injected by init.sh | ✅ Accepted | 2026-06-03 |
| [ADR-002](002-shared-workspace-bootstrap-library.md) | Shared workspace-bootstrap library sourced by setup, create, and init | ✅ Accepted | 2026-07-25 |
| [ADR-003](003-safe-workspace-deletion.md) | Safe, ordered workspace deletion via delete-workspace.sh | ✅ Accepted | 2026-07-25 |
| [ADR-004](004-per-slot-e2e-infrastructure.md) | Per-slot lightweight E2E infrastructure, local Cypress over shared VNC/Docker Cypress | ✅ Accepted | 2026-06-07 |
| [ADR-005](005-opt-in-pgadmin-service.md) | Opt-in pgAdmin service under the tools Compose profile | ✅ Accepted | 2026-08-17 |

---

## Status legend

| Badge | Meaning |
|-------|---------|
| ✅ Accepted | Decision is in effect |
| 🔄 Proposed | Under discussion, not yet implemented |
| ⛔ Deprecated | No longer applies — see linked ADR for replacement |
| 🔁 Superseded | Replaced by a newer ADR (link provided in the document) |
