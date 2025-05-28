.PHONY: init help clean status clean-proxy hosts-help add-host remove-host list-hosts

# Default values (only used for init when not specified)
DEFAULT_PROJECT_NAME ?= laravel-app

help: ## Show this help message
	@echo "Laravel Container Initialization with Virtual Hosts"
	@echo "=================================================="
	@echo ""
	@echo "Usage: make init PROJECT_NAME=<name>"
	@echo ""
	@echo "Parameters:"
	@echo "  PROJECT_NAME  - Name of the Laravel project (default: laravel-app)"
	@echo "                  Virtual host will be: <PROJECT_NAME>.loc"
	@echo ""
	@echo "Examples:"
	@echo "  make init PROJECT_NAME=my-app     # Creates virtual host: my-app.loc"
	@echo "  make init PROJECT_NAME=blog       # Creates virtual host: blog.loc"
	@echo "  make status PROJECT_NAME=my-app"
	@echo "  make clean PROJECT_NAME=my-app"
	@echo "  make add-host PROJECT_NAME=my-app"
	@echo ""
	@echo "Note: After initialization, add the following to your /etc/hosts file:"
	@echo "      127.0.0.1 <PROJECT_NAME>.loc"
	@echo ""
	@echo "Available targets:"
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  %-15s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

init: ## Initialize a new Laravel project with Docker containers and virtual host
	@if [ -z "$(PROJECT_NAME)" ]; then \
		PROJECT_NAME="$(DEFAULT_PROJECT_NAME)"; \
		echo "⚠️  No PROJECT_NAME specified, using default: $$PROJECT_NAME"; \
		echo "Usage: make init PROJECT_NAME=<name>"; \
	else \
		PROJECT_NAME="$(PROJECT_NAME)"; \
	fi; \
	echo "🚀 Initializing Laravel project: $$PROJECT_NAME"; \
	echo "🌐 Virtual Host: $$PROJECT_NAME.loc"; \
	echo "📁 Location: /var/www/$$PROJECT_NAME"; \
	echo ""; \
	./init-laravel-container.sh $$PROJECT_NAME /var/www $${PROJECT_NAME}_volume; \
	echo ""; \
	echo "🔧 To access your application, add this line to your /etc/hosts file:"; \
	echo "   127.0.0.1 $$PROJECT_NAME.loc"; \
	echo ""; \
	echo "Then visit: http://$$PROJECT_NAME.loc"; \
	echo ""; \
	echo "💡 Quick hosts file management:"; \
	echo "   ./manage-hosts.sh add $$PROJECT_NAME    # Add hosts entry"; \
	echo "   ./manage-hosts.sh remove $$PROJECT_NAME # Remove hosts entry"

status: ## Check the status of a Laravel project
	@if [ -z "$(PROJECT_NAME)" ]; then \
		echo "❌ PROJECT_NAME is required"; \
		echo "Usage: make status PROJECT_NAME=<name>"; \
		exit 1; \
	fi
	@echo "📊 Status for project: $(PROJECT_NAME)"
	@echo "================================"
	@echo ""
	@echo "🐳 Docker Containers:"
	@docker ps --filter "name=$(PROJECT_NAME)" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || echo "No containers found"
	@echo ""
	@echo "💾 Docker Volumes:"
	@docker volume ls --filter "name=$(PROJECT_NAME)" --format "table {{.Name}}\t{{.Driver}}" 2>/dev/null || echo "No volumes found"
	@echo ""
	@echo "🌐 Networks:"
	@docker network ls --filter "name=$(PROJECT_NAME)" --format "table {{.Name}}\t{{.Driver}}" 2>/dev/null || echo "No networks found"
	@echo ""
	@if docker exec $(PROJECT_NAME)_php test -f /var/www/artisan 2>/dev/null; then \
		echo "✅ Laravel Status: Running"; \
		docker exec $(PROJECT_NAME)_php php /var/www/artisan --version 2>/dev/null || echo "⚠️  Artisan command failed"; \
	else \
		echo "❌ Laravel Status: Not found or not running"; \
	fi

clean: ## Remove Docker containers and volumes for a project
	@if [ -z "$(PROJECT_NAME)" ]; then \
		echo "❌ PROJECT_NAME is required"; \
		echo "Usage: make clean PROJECT_NAME=<name>"; \
		exit 1; \
	fi
	@echo "🧹 Cleaning up project: $(PROJECT_NAME)"
	@echo "Stopping and removing containers..."
	@docker-compose -p $(PROJECT_NAME) -f /var/www/$(PROJECT_NAME)/docker-compose.yml down -v --remove-orphans 2>/dev/null || true
	@docker stop $(PROJECT_NAME)_php $(PROJECT_NAME)_nginx 2>/dev/null || true
	@docker rm $(PROJECT_NAME)_php $(PROJECT_NAME)_nginx 2>/dev/null || true
	@echo "Removing volumes..."
	@docker volume rm $(PROJECT_NAME)_volume --force 2>/dev/null || true
	@docker volume rm $(PROJECT_NAME)_$(PROJECT_NAME)_volume --force 2>/dev/null || true
	@echo "Removing networks..."
	@docker network rm $(PROJECT_NAME)_net 2>/dev/null || true
	@docker network rm $(PROJECT_NAME)_$(PROJECT_NAME)_net 2>/dev/null || true
	@echo "Removing project directory..."
	@rm -rf /var/www/$(PROJECT_NAME) 2>/dev/null || true
	@echo "✅ Cleanup completed for $(PROJECT_NAME)"
	@echo ""
	@echo "🔧 Don't forget to remove this line from your /etc/hosts file:"
	@echo "   127.0.0.1 $(PROJECT_NAME).loc"
	@echo ""
	@echo "💡 To clean up the reverse proxy (affects all projects):"
	@echo "   make clean-proxy"

clean-proxy: ## Remove the shared reverse proxy container
	@echo "🧹 Cleaning up reverse proxy..."
	@docker stop laravel_proxy 2>/dev/null || true
	@docker rm laravel_proxy 2>/dev/null || true
	@docker network rm laravel_proxy_net 2>/dev/null || true
	@echo "✅ Reverse proxy cleanup completed"
	@echo "⚠️  Note: This will affect all Laravel projects using virtual hosts"

hosts-help: ## Show instructions for managing /etc/hosts file
	@echo "📝 Managing /etc/hosts file:"
	@echo "=========================="
	@echo ""
	@echo "Using the hosts management script:"
	@echo "  ./manage-hosts.sh add <project_name>     # Add virtual host"
	@echo "  ./manage-hosts.sh remove <project_name>  # Remove virtual host"
	@echo "  ./manage-hosts.sh list                   # List all entries"
	@echo ""
	@echo "Manual management:"
	@echo "  sudo echo '127.0.0.1 $(PROJECT_NAME).loc' >> /etc/hosts"
	@echo "  sudo sed -i '/127.0.0.1 $(PROJECT_NAME).loc/d' /etc/hosts"
	@echo ""
	@echo "To view current entries:"
	@echo "  grep '127.0.0.1.*\.loc' /etc/hosts"

add-host: ## Add virtual host entry to /etc/hosts file
	@if [ -z "$(PROJECT_NAME)" ]; then \
		echo "❌ PROJECT_NAME is required"; \
		echo ""; \
		echo "Correct usage:"; \
		echo "  make add-host PROJECT_NAME=<name>"; \
		echo ""; \
		echo "Examples:"; \
		echo "  make add-host PROJECT_NAME=pilot"; \
		echo "  make add-host PROJECT_NAME=blog"; \
		echo ""; \
		echo "❌ Wrong: make add-host pilot"; \
		echo "✅ Right: make add-host PROJECT_NAME=pilot"; \
		exit 1; \
	fi
	./manage-hosts.sh add $(PROJECT_NAME)

remove-host: ## Remove virtual host entry from /etc/hosts file
	@if [ -z "$(PROJECT_NAME)" ]; then \
		echo "❌ PROJECT_NAME is required"; \
		echo ""; \
		echo "Correct usage:"; \
		echo "  make remove-host PROJECT_NAME=<name>"; \
		echo ""; \
		echo "Examples:"; \
		echo "  make remove-host PROJECT_NAME=pilot"; \
		echo "  make remove-host PROJECT_NAME=blog"; \
		echo ""; \
		echo "❌ Wrong: make remove-host pilot"; \
		echo "✅ Right: make remove-host PROJECT_NAME=pilot"; \
		exit 1; \
	fi
	./manage-hosts.sh remove $(PROJECT_NAME)

list-hosts: ## List all Laravel virtual host entries
	./manage-hosts.sh list
