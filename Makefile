.PHONY: help doctor install setup up down logs init reset-db add-agent

AGENT  ?=
PHP    ?=
NODE   ?=
AGENTS ?= 1
BRANCH ?=
REPO   ?=

help:
	@echo ""
	@echo "  sushigo-dev-lab commands"
	@echo ""
	@echo "  make setup                    Initialize lab with 1 agent"
	@echo "  make setup AGENTS=3           Initialize lab with N agents"
	@echo "  make setup AGENTS=2 BRANCH=feat/x  Init agents on a specific branch"
	@echo "  make doctor                   Check all prerequisites"
	@echo "  make install                  Install missing prerequisites via Homebrew"
	@echo "  make install PHP=8.2 NODE=20  Install with specific versions"
	@echo "  make up                       Start shared Docker services"
	@echo "  make down                     Stop shared Docker services"
	@echo "  make logs                     Follow Docker service logs"
	@echo "  make init                     Start all agents"
	@echo "  make init AGENT=agent-a       Start a specific agent (foreground)"
	@echo "  make add-agent                Add a new agent clone"
	@echo "  make add-agent BRANCH=feat/x  Add a new agent on a specific branch"
	@echo "  make reset-db AGENT=agent-a   Wipe and re-seed one agent database"
	@echo ""

doctor:
	@./scripts/check-prereqs.sh

setup:
	@./scripts/setup.sh \
		--agents=$(AGENTS) \
		$(if $(BRANCH),--branch=$(BRANCH),) \
		$(if $(REPO),--repo=$(REPO),)

install:
	@./scripts/install-prereqs.sh \
		$(if $(PHP),--php=$(PHP),) \
		$(if $(NODE),--node=$(NODE),)

up:
	docker compose up -d
	@echo "✅ Shared services running (PostgreSQL, Redis, Mailpit)"
	@echo "   Mailpit UI → http://localhost:8025"

down:
	docker compose down

logs:
	docker compose logs -f

init:
	@./scripts/init.sh $(AGENT)

add-agent:
	@./scripts/create-agent.sh $(if $(BRANCH),--branch=$(BRANCH),)

reset-db:
ifndef AGENT
	$(error AGENT is required. Usage: make reset-db AGENT=agent-a)
endif
	@./scripts/reset-agent-db.sh $(AGENT)
