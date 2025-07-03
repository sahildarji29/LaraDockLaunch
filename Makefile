.PHONY: init help clean status clean-proxy hosts-help add-host remove-host list-hosts build-master clean-master

# Default values
DEFAULT_PROJECT_NAME ?= laravel-app
DEFAULT_DOMAIN ?= loc

help: ## Show this help message
	@echo "Laravel Container Initialization with Virtual Hosts"
	@echo "=================================================="
	@echo ""
	@echo "Usage: make init PROJECT_NAME=<n> [DOMAIN=<domain>]"
	@echo ""
	@echo "Parameters:"
	@echo "  PROJECT_NAME - Name of the Laravel project (default: laravel-app)"
	@echo "  DOMAIN      - Domain for the virtual host (default: loc)"
	@echo ""
	@echo "Virtual Host:"
	@echo "  Format: PROJECT_NAME.DOMAIN (e.g., myapp.loc, myapp.test, myapp.com)"
	@echo ""
	@echo "Examples:"
	@echo "  make init PROJECT_NAME=my-app                # Creates: my-app.loc"
	@echo "  make init PROJECT_NAME=blog DOMAIN=test     # Creates: blog.test"
	@echo "  make init PROJECT_NAME=api DOMAIN=com       # Creates: api.com"
	@echo ""
	@echo "Available Commands:"
	@echo "  make init PROJECT_NAME=<name>      # Initialize new project"
	@echo "  make status PROJECT_NAME=<name>    # Check project status"
	@echo "  make clean PROJECT_NAME=<name>     # Remove project"
	@echo "  make add-host PROJECT_NAME=<name>  # Add hosts entry"
	@echo "  make remove-host PROJECT_NAME=<name> # Remove hosts entry"
	@echo "  make build-master                  # Build master image"
	@echo "  make clean-master                  # Remove master image"
	@echo ""
	@echo "Project Setup:"
	@echo "  1. Files location: /var/www/copilot-infra/<PROJECT_NAME>"
	@echo "  2. File ownership: www-data:www-data"
	@echo "  3. Hosts entry: 127.0.0.1 <PROJECT_NAME>.<DOMAIN>"
	@echo "  4. Node.js and npm available in container"

init: ## Initialize a new Laravel project with Docker containers
	@if [ -z "$(PROJECT_NAME)" ]; then \
		PROJECT_NAME="$(DEFAULT_PROJECT_NAME)"; \
		echo "⚠️  No PROJECT_NAME specified, using default: $$PROJECT_NAME"; \
		echo "Usage: make init PROJECT_NAME=<n> [DOMAIN=<domain>]"; \
	else \
		PROJECT_NAME="$(PROJECT_NAME)"; \
	fi; \
	if [ -z "$(DOMAIN)" ]; then \
		DOMAIN="$(DEFAULT_DOMAIN)"; \
	else \
		DOMAIN="$(DOMAIN)"; \
	fi; \
	echo "🚀 Initializing Laravel project: $$PROJECT_NAME"; \
	echo "🌐 Virtual Host: $$PROJECT_NAME.$$DOMAIN"; \
	echo "📁 Location: /var/www/copilot-infra/$$PROJECT_NAME"; \
	./init-laravel-container.sh "$$PROJECT_NAME" "/var/www/copilot-infra"

status: ## Show status of Laravel containers
	@if [ -z "$(PROJECT_NAME)" ]; then \
		echo "⚠️  Please specify PROJECT_NAME"; \
		echo "Usage: make status PROJECT_NAME=<name>"; \
		exit 1; \
	fi; \
	echo "📊 Checking status for project: $(PROJECT_NAME)"; \
	docker ps --filter "name=$(PROJECT_NAME)_" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"; \
	echo ""; \
	if [ -f /tmp/laravel_proxy_port ]; then \
		source /tmp/laravel_proxy_port; \
		if [ -n "$$PROXY_PORT" ]; then \
			echo "✅ Running on port $$PROXY_PORT"; \
			echo "🔗 Access URL: http://$(PROJECT_NAME).$$DOMAIN:$$PROXY_PORT"; \
		else \
			echo "✅ Running (port unknown)"; \
		fi; \
	else \
		echo "⚠️  Proxy port information not found"; \
	fi

clean: ## Remove Docker containers and volumes for a project
	@if [ -z "$(PROJECT_NAME)" ]; then \
		echo "⚠️  Please specify PROJECT_NAME"; \
		echo "Usage: make clean PROJECT_NAME=<name>"; \
		exit 1; \
	fi; \
	echo "🧹 Cleaning up project: $(PROJECT_NAME)"; \
	echo "📦 Preserving master image: laravel-master:latest"; \
	echo "Stopping and removing containers..."; \
	docker-compose -p $(PROJECT_NAME) -f /var/www/copilot-infra/$(PROJECT_NAME)/docker-compose.yml down -v --remove-orphans 2>/dev/null || true; \
	docker stop $(PROJECT_NAME)_php $(PROJECT_NAME)_nginx 2>/dev/null || true; \
	docker rm $(PROJECT_NAME)_php $(PROJECT_NAME)_nginx 2>/dev/null || true; \
	echo "Removing networks..."; \
	docker network rm $(PROJECT_NAME)_net 2>/dev/null || true; \
	docker network rm $(PROJECT_NAME)_$(PROJECT_NAME)_net 2>/dev/null || true; \
	echo "Removing project directory..."; \
	rm -rf /var/www/copilot-infra/$(PROJECT_NAME) 2>/dev/null || true; \
	echo "✅ Cleanup completed for $(PROJECT_NAME)"; \
	echo "✅ Master image preserved for faster future deployments"; \
	echo ""; \
	echo "🔧 Don't forget to remove hosts entry:"; \
	echo "   make remove-host PROJECT_NAME=$(PROJECT_NAME)"

clean-proxy: ## Remove the shared reverse proxy container
	@echo "🧹 Cleaning up reverse proxy..."
	@docker stop laravel_proxy 2>/dev/null || true
	@docker rm laravel_proxy 2>/dev/null || true
	@docker network rm laravel_proxy_net 2>/dev/null || true
	@echo "✅ Reverse proxy cleanup completed"
	@echo "⚠️  Note: This will affect all Laravel projects"

add-host: ## Add virtual host entry to /etc/hosts file
	@if [ -z "$(PROJECT_NAME)" ]; then \
		echo "⚠️  Please specify PROJECT_NAME"; \
		echo "Usage: make add-host PROJECT_NAME=<name>"; \
		exit 1; \
	fi; \
	if ! grep -q "127.0.0.1[[:space:]]$(PROJECT_NAME).$$DOMAIN" /etc/hosts; then \
		echo "🔧 Adding host entry for $(PROJECT_NAME).$$DOMAIN"; \
		sudo sh -c 'echo "127.0.0.1 $(PROJECT_NAME).$$DOMAIN" >> /etc/hosts'; \
		echo "✅ Host entry added successfully"; \
	else \
		echo "✅ Host entry already exists"; \
	fi

remove-host: ## Remove virtual host entry from /etc/hosts file
	@if [ -z "$(PROJECT_NAME)" ]; then \
		echo "⚠️  Please specify PROJECT_NAME"; \
		echo "Usage: make remove-host PROJECT_NAME=<name>"; \
		exit 1; \
	fi; \
	echo "🔧 Removing host entry for $(PROJECT_NAME).$$DOMAIN"; \
	sudo sed -i "/127.0.0.1[[:space:]]$(PROJECT_NAME).$$DOMAIN/d" /etc/hosts; \
	echo "✅ Host entry removed successfully"

hosts: ## Show all Laravel virtual host entries in /etc/hosts file
	@echo "📋 Current Laravel virtual host entries:"
	@echo ""
	@grep "127.0.0.1.*\.$$DOMAIN" /etc/hosts || echo "No entries found"
	@echo ""
	@echo "Host Management Commands:"
	@echo "  make add-host PROJECT_NAME=<name>    # Add entry"
	@echo "  make remove-host PROJECT_NAME=<name> # Remove entry"

build-master: ## Build the master Laravel image with Node.js support
	@echo "🏗️  Building master Laravel image with Node.js support..."
	@echo "⏳ This may take a few minutes..."
	@docker build -f Dockerfile.master -t laravel-master:latest .
	@echo "✅ Master image built successfully!"
	@echo "💡 This image will be used for all new Laravel projects"

clean-master: ## Remove the master Laravel image
	@echo "⚠️  WARNING: This will remove the master image used by ALL projects!"
	@echo ""
	@read -p "Are you sure? (y/N): " confirm; \
	if [ "$$confirm" = "y" ] || [ "$$confirm" = "Y" ]; then \
		echo "🗑️  Removing master Laravel image..."; \
		docker rmi laravel-master:latest 2>/dev/null || echo "Image not found"; \
		echo "✅ Master image removed"; \
		echo "💡 Run 'make build-master' to rebuild"; \
	else \
		echo "❌ Operation cancelled"; \
	fi
