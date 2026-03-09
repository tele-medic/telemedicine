.PHONY: init clone build up down logs test clean

# Clone all submodules
init:
	git submodule update --init --recursive

# Pull latest for all submodules
pull:
	git submodule foreach 'git checkout main && git pull origin main'

# Build all services
build:
	docker compose build

# Start all services
up:
	docker compose up -d

# Stop all services
down:
	docker compose down

# View logs
logs:
	docker compose logs -f

# Run tests across all Go services
test:
	@for dir in shared services/session services/gateway services/turn services/webhook services/recording services/notify; do \
		if [ -f "$$dir/go.mod" ]; then \
			echo "=== Testing $$dir ===" && \
			cd $$dir && go test ./... && cd -; \
		fi \
	done

# Clean up
clean:
	docker compose down -v --remove-orphans
	docker system prune -f
