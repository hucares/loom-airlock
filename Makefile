IMAGE := loom-airlock
CONTAINER := loom
WORKSPACE ?= $(shell pwd)/../events_radar

# Auth volumes - mount host credentials into container
GH_AUTH := $(HOME)/.config/gh
CLAUDE_AUTH := $(HOME)/.claude
SSH_AUTH := $(HOME)/.ssh

.PHONY: build create start stop attach shell logs daemon auth run clean nuke status

# Build the image
build:
	docker build -t $(IMAGE) .

# Create persistent container (run once)
create: build
	@if docker ps -a --format '{{.Names}}' | grep -q '^$(CONTAINER)$$'; then \
		echo "Container '$(CONTAINER)' already exists. Run 'make clean' first to recreate."; \
	else \
		docker create -it \
			--name $(CONTAINER) \
			-v $(WORKSPACE):/workspace \
			-v $(GH_AUTH):/root/.config/gh \
			-v $(CLAUDE_AUTH):/root/.claude \
			-v $(SSH_AUTH):/root/.ssh:ro \
			--env-file .env \
			$(IMAGE) bash \
		&& echo "Container '$(CONTAINER)' created. Run 'make start' to enter." \
		|| { echo "Failed to create container."; exit 1; }; \
	fi

# Start and attach to the container
start:
	@docker start -ai $(CONTAINER)

# Stop the container
stop:
	@docker stop $(CONTAINER) 2>/dev/null || true

# Attach to running container
attach:
	@docker attach $(CONTAINER)

# Open another shell into running container
shell:
	@docker exec -it $(CONTAINER) bash

# Tail daemon logs inside the container
logs:
	@docker exec -it $(CONTAINER) bash -c 'tail -f /workspace/.loom/logs/loom-shepherd-*.log'

# Authenticate Claude Code and GitHub (first-time setup)
auth:
	@docker start $(CONTAINER) >/dev/null 2>&1 || true
	@echo "=== Authenticating GitHub ==="
	@docker exec -it $(CONTAINER) bash -c 'gh auth login'
	@echo ""
	@echo "=== Authenticating Claude Code ==="
	@docker exec -it $(CONTAINER) bash -c 'claude /login'
	@echo ""
	@echo "=== Authentication complete ==="

# Start container and launch daemon
run:
	@docker start $(CONTAINER) >/dev/null 2>&1 || true
	@docker exec -it $(CONTAINER) bash -c \
		'unset CLAUDECODE && ./.loom/scripts/loom-daemon.sh --merge'

# Start daemon directly (container must be running)
daemon:
	@docker exec -it $(CONTAINER) bash -c \
		'unset CLAUDECODE && ./.loom/scripts/loom-daemon.sh --merge'

# Show container status
status:
	@docker ps -a --filter name=$(CONTAINER) --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'

# Remove container (keeps image)
clean:
	@docker stop $(CONTAINER) 2>/dev/null || true
	@docker rm $(CONTAINER) 2>/dev/null || true
	@echo "Container removed. Run 'make create' to recreate."

# Remove everything
nuke: clean
	@docker rmi $(IMAGE) 2>/dev/null || true
	@echo "Image and container removed."
