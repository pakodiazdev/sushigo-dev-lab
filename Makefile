.PHONY: help doctor install setup up down logs init status reset-db add-workspace delete-workspace update-workspaces e2e e2e-stop cypress cypress-run

WORKSPACE ?=
PHP    ?=
NODE   ?=
WORKSPACES ?=
BRANCH ?=
REPO   ?=

help:
	@echo ""
	@echo "  sushigo-dev-lab commands"
	@echo ""
	@echo "  make setup                          Initialize lab with 1 workspace"
	@echo "  make setup WORKSPACES=3             Initialize lab with N workspaces"
	@echo "  make setup WORKSPACES=2 BRANCH=feat/x  Init workspaces on a specific branch"
	@echo "  make doctor                         Check all prerequisites"
	@echo "  make install                        Install missing prerequisites via Homebrew"
	@echo "  make install PHP=8.2 NODE=20        Install with specific versions"
	@echo "  make up                             Start Docker services + all workspaces (PHP + Vite)"
	@echo "  make up WORKSPACES=2                Start Docker services + N workspaces"
	@echo "  make down                           Stop all workspaces (Overmind) + Docker services"
	@echo "  make logs                           Follow Docker service logs"
	@echo "  make init WORKSPACE=sushigo-a       Start a specific workspace (foreground)"
	@echo "  make status                         Show every workspace slot's branch, ports and runtime state"
	@echo "  make add-workspace                  Add a new workspace clone"
	@echo "  make add-workspace BRANCH=feat/x    Add a new workspace on a specific branch"
	@echo "  make reset-db WORKSPACE=sushigo-a   Wipe and re-seed one workspace database"
	@echo "  make delete-workspace WORKSPACE=sushigo-a  Remove one workspace slot (Overmind + DB + dir)"
	@echo "  make update-workspaces               Switch every workspace to main and pull latest"
	@echo "  make e2e WORKSPACE=sushigo-a          Start E2E stack (container + Vite) for a workspace"
	@echo "  make e2e-stop WORKSPACE=sushigo-a     Stop E2E stack for a workspace"
	@echo "  make cypress WORKSPACE=sushigo-a      Open Cypress GUI against the running E2E stack"
	@echo "  make cypress-run WORKSPACE=sushigo-a  Run Cypress headless (CI-style)"
	@echo ""

doctor:
	@./scripts/check-prereqs.sh

setup:
	@./scripts/setup.sh \
		--workspaces=$(or $(WORKSPACES),1) \
		$(if $(BRANCH),--branch=$(BRANCH),) \
		$(if $(REPO),--repo=$(REPO),)

install:
	@./scripts/install-prereqs.sh \
		$(if $(PHP),--php=$(PHP),) \
		$(if $(NODE),--node=$(NODE),)

up:
	@./scripts/init.sh $(if $(filter-out 0,$(WORKSPACES)),--count=$(WORKSPACES),)

down:
	@for dir in workspaces/*/; do \
		if [ -S "$$dir/.overmind.sock" ]; then \
			echo "⏹  Stopping workspace: $$dir"; \
			(cd "$$dir" && overmind quit) 2>/dev/null || true; \
		fi; \
	done
	docker compose down 2>/dev/null || true
	@echo "✅ All services stopped"

logs:
	docker compose logs -f

init:
	@./scripts/init.sh $(WORKSPACE)

status:
	@./scripts/status.sh

add-workspace:
	@./scripts/create-workspace.sh $(if $(BRANCH),--branch=$(BRANCH),)

reset-db:
ifeq ($(strip $(WORKSPACE)),)
	$(error WORKSPACE is required. Usage: make reset-db WORKSPACE=sushigo-a)
endif
	@./scripts/reset-workspace-db.sh $(WORKSPACE)

delete-workspace:
ifeq ($(strip $(WORKSPACE)),)
	$(error WORKSPACE is required. Usage: make delete-workspace WORKSPACE=sushigo-a)
endif
	@./scripts/delete-workspace.sh $(WORKSPACE)

update-workspaces:
	@./scripts/update-workspaces.sh

e2e:
ifeq ($(strip $(WORKSPACE)),)
	$(error WORKSPACE is required. Usage: make e2e WORKSPACE=sushigo-a)
endif
	@./scripts/start-e2e.sh $(WORKSPACE)

e2e-stop:
ifeq ($(strip $(WORKSPACE)),)
	$(error WORKSPACE is required. Usage: make e2e-stop WORKSPACE=sushigo-a)
endif
	@./scripts/stop-e2e.sh $(WORKSPACE)

cypress:
ifeq ($(strip $(WORKSPACE)),)
	$(error WORKSPACE is required. Usage: make cypress WORKSPACE=sushigo-a)
endif
	@./scripts/cypress.sh $(WORKSPACE)

cypress-run:
ifeq ($(strip $(WORKSPACE)),)
	$(error WORKSPACE is required. Usage: make cypress-run WORKSPACE=sushigo-a)
endif
	@./scripts/cypress.sh $(WORKSPACE) --run
