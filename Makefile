.PHONY: init help clean status clean-nginx hosts-help add-host remove-host list-hosts build-master clean-master

# Default values
DEFAULT_PROJECT_NAME ?= laravel-app
DEFAULT_DOMAIN ?= loc

help: ## Show this help message
	@echo "High-Scale Laravel Container Infrastructure"
	@echo "=========================================="
	@echo ""
	@echo "Optimized for 300-400 containers on single instance"
	@echo "Architecture: Shared Nginx + Individual PHP-FPM containers"
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
	@echo "  make clean-nginx                   # Remove shared nginx container"
	@echo ""
	@echo "High-Scale Features:"
	@echo "  • 50% fewer containers (1 shared nginx vs per-project nginx)"
	@echo "  • Single shared network reduces overhead"
	@echo "  • Named volumes ensure data persistence"
	@echo "  • Resource limits: 256MB RAM, 0.5 CPU per container"
	@echo "  • Optimized nginx configuration for performance"
	@echo ""
	@echo "Project Setup:"
	@echo "  1. Files location: Local directory (/var/www/copilot-infra/PROJECT_NAME)"
	@echo "  2. Nginx configs: /var/www/nginx-configs/"
	@echo "  3. Hosts entry: 127.0.0.1 <PROJECT_NAME>.<DOMAIN>"
	@echo "  4. Node.js and npm available in container"
	@echo "  5. Data persists across container restarts"
	@echo "  • Bind mounts ensure direct filesystem access"
	@echo ""
	@echo "📊 Monitoring:"
	@echo "  make containers          - List all containers"
	@echo "  make resources           - Show resource usage"
	@echo "  make logs PROJECT_NAME=<name> - Show project logs"
	@echo ""

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
	echo "📁 Location: Local directory (/var/www/copilot-infra/$$PROJECT_NAME)"; \
	echo "⚙️  Architecture: Shared Nginx + Individual PHP-FPM"; \
	./init-laravel-container.sh "$$PROJECT_NAME" "/var/www/copilot-infra"

status: ## Show status of Laravel containers
	@if [ -z "$(PROJECT_NAME)" ]; then \
		echo "⚠️  Please specify PROJECT_NAME"; \
		echo "Usage: make status PROJECT_NAME=<name>"; \
		exit 1; \
	fi; \
	echo "📊 Checking status for project: $(PROJECT_NAME)"; \
	echo ""; \
	echo "PHP-FPM Container:"; \
	docker ps --filter "name=$(PROJECT_NAME)_php" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" || echo "No PHP-FPM container found"; \
	echo ""; \
	echo "Shared Nginx Container:"; \
	docker ps --filter "name=laravel_nginx_shared" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" || echo "No shared nginx container found"; \
	echo ""; \
	echo "Project Directory:"; \
	if [ -d "/var/www/copilot-infra/$(PROJECT_NAME)" ]; then \
		echo "✅ Project directory: /var/www/copilot-infra/$(PROJECT_NAME)"; \
		ls -la "/var/www/copilot-infra/$(PROJECT_NAME)" | head -5; \
	else \
		echo "❌ Project directory not found"; \
	fi; \
	echo ""; \
	echo "Shared Network:"; \
	docker network ls --filter "name=laravel_shared_net" --format "table {{.Driver}}\t{{.Name}}" || echo "No shared network found"; \
	echo ""; \
	if [ -f /tmp/laravel_nginx_port ]; then \
		source /tmp/laravel_nginx_port; \
		if [ -n "$$NGINX_PORT" ]; then \
			echo "✅ Shared nginx running on port $$NGINX_PORT"; \
			echo "🔗 Access URL: http://$(PROJECT_NAME).$$DOMAIN:$$NGINX_PORT"; \
		else \
			echo "✅ Running (port unknown)"; \
		fi; \
	else \
		echo "⚠️  Nginx port information not found"; \
	fi

clean: ## Remove Docker containers and volumes for a project
	@if [ -z "$(PROJECT_NAME)" ]; then \
		echo "⚠️  Please specify PROJECT_NAME"; \
		echo "Usage: make clean PROJECT_NAME=<name>"; \
		exit 1; \
	fi; \
	echo "🧹 Cleaning up project: $(PROJECT_NAME)"; \
	echo "📦 Preserving master image and shared nginx"; \
	echo "Stopping and removing PHP-FPM container..."; \
	docker-compose -p $(PROJECT_NAME) -f /var/www/copilot-infra/$(PROJECT_NAME)/docker-compose.yml down -v --remove-orphans 2>/dev/null || true; \
	docker stop $(PROJECT_NAME)_php 2>/dev/null || true; \
	docker rm $(PROJECT_NAME)_php 2>/dev/null || true; \
	echo "Removing log volumes..."; \
	docker volume rm $(PROJECT_NAME)_logs 2>/dev/null || true; \
	echo "Removing nginx configuration..."; \
	rm -f /var/www/nginx-configs/$(PROJECT_NAME).conf 2>/dev/null || true; \
	echo "Removing project directory..."; \
	rm -rf /var/www/copilot-infra/$(PROJECT_NAME) 2>/dev/null || true; \
	echo "Reloading nginx configuration..."; \
	docker exec laravel_nginx_shared nginx -s reload 2>/dev/null || echo "⚠️  Nginx reload failed (container may not be running)"; \
	echo "✅ Cleanup completed for $(PROJECT_NAME)"; \
	echo "✅ Master image and shared nginx preserved"; \
	echo "✅ Data persistence: Project directory removed"; \
	echo ""; \
	echo "🔧 Don't forget to remove hosts entry:"; \
	echo "   make remove-host PROJECT_NAME=$(PROJECT_NAME)"

clean-nginx: ## Remove the shared nginx container
	@echo "🧹 Cleaning up shared nginx container..."
	@echo "⚠️  WARNING: This will affect ALL Laravel projects!"
	@echo ""
	@read -p "Are you sure? (y/N): " confirm; \
	if [ "$$confirm" = "y" ] || [ "$$confirm" = "Y" ]; then \
		docker stop laravel_nginx_shared 2>/dev/null || true; \
		docker rm laravel_nginx_shared 2>/dev/null || true; \
		echo "✅ Shared nginx container removed"; \
		echo "💡 Next project initialization will recreate it"; \
	else \
		echo "❌ Operation cancelled"; \
	fi

add-host: ## Add virtual host entry to /etc/hosts file
	@if [ -z "$(PROJECT_NAME)" ]; then \
		echo "⚠️  Please specify PROJECT_NAME"; \
		echo "Usage: make add-host PROJECT_NAME=<name>"; \
		exit 1; \
	fi; \
	if [ -z "$(DOMAIN)" ]; then \
		DOMAIN="$(DEFAULT_DOMAIN)"; \
	else \
		DOMAIN="$(DOMAIN)"; \
	fi; \
	if ! grep -q "127.0.0.1[[:space:]]$(PROJECT_NAME).$$DOMAIN" /etc/hosts; then \
		echo "🔧 Adding host entry for $(PROJECT_NAME).$$DOMAIN"; \
		echo "127.0.0.1 $(PROJECT_NAME).$$DOMAIN" | sudo tee -a /etc/hosts > /dev/null; \
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
	if [ -z "$(DOMAIN)" ]; then \
		DOMAIN="$(DEFAULT_DOMAIN)"; \
	else \
		DOMAIN="$(DOMAIN)"; \
	fi; \
	echo "🔧 Removing host entry for $(PROJECT_NAME).$$DOMAIN"; \
	sudo sed -i "/127.0.0.1[[:space:]]$(PROJECT_NAME).$$DOMAIN/d" /etc/hosts; \
	echo "✅ Host entry removed successfully"

hosts: ## Show all Laravel virtual host entries in /etc/hosts file
	@echo "📋 Current Laravel virtual host entries:"
	@echo ""
	@if [ -z "$(DOMAIN)" ]; then \
		DOMAIN="$(DEFAULT_DOMAIN)"; \
	else \
		DOMAIN="$(DOMAIN)"; \
	fi; \
	grep "127.0.0.1.*\.$$DOMAIN" /etc/hosts || echo "No entries found"; \
	echo ""
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

# High-scale deployment helpers
scale-info: ## Show scaling information and recommendations
	@echo "📊 High-Scale Laravel Container Infrastructure"
	@echo "============================================="
	@echo ""
	@echo "Current Architecture Benefits:"
	@echo "  • 50% fewer containers (1 shared nginx vs per-project nginx)"
	@echo "  • Single shared network reduces overhead"
	@echo "  • Named volumes ensure data persistence"
	@echo "  • Resource limits prevent resource exhaustion"
	@echo "  • Optimized nginx configuration for performance"
	@echo ""
	@echo "Resource Allocation per Container:"
	@echo "  • Memory Limit: 256MB"
	@echo "  • CPU Limit: 0.5 cores"
	@echo "  • Memory Reservation: 128MB"
	@echo "  • CPU Reservation: 0.25 cores"
	@echo ""
	@echo "Estimated Resource Usage (400 containers):"
	@echo "  • Total Memory: ~100GB (256MB × 400)"
	@echo "  • Total CPU: ~200 cores (0.5 × 400)"
	@echo "  • Recommended: 64+ cores, 128GB+ RAM"
	@echo ""
	@echo "Container Counts:"
	@echo "  • PHP-FPM Containers: 1 per project"
	@echo "  • Shared Nginx: 1 total"
	@echo "  • Networks: 1 shared network"
	@echo "  • Volumes: 1 per project (persistent data)"
	@echo ""
	@echo "Security Features:"
	@echo "  • Data isolation via named volumes"
	@echo "  • Network isolation within shared network"
	@echo "  • Resource limits prevent DOS attacks"
	@echo "  • Nginx security headers enabled"

monitoring: ## Show monitoring commands for high-scale deployment
	@echo "📈 Monitoring Commands for High-Scale Deployment"
	@echo "==============================================="
	@echo ""
	@echo "Container Status:"
	@echo "  docker ps | grep -E '(laravel|php)' | wc -l    # Count running containers"
	@echo "  docker ps -a | grep -E '(laravel|php)' | wc -l # Count all containers"
	@echo ""
	@echo "Resource Usage:"
	@echo "  docker stats --no-stream | grep -E '(laravel|php)' # Resource usage"
	@echo "  docker system df                                   # Disk usage"
	@echo ""
	@echo "Network Status:"
	@echo "  docker network ls | grep laravel                   # Networks"
	@echo "  docker network inspect laravel_shared_net         # Network details"
	@echo ""
	@echo "Volume Status:"
	@echo "  docker volume ls | grep '_data' | wc -l           # Count volumes"
	@echo "  docker system df -v                               # Volume usage"
	@echo ""
	@echo "Nginx Status:"
	@echo "  docker exec laravel_nginx_shared nginx -T         # Test config"
	@echo "  docker logs laravel_nginx_shared --tail 50        # Recent logs"

containers: ## List all Laravel containers
	@echo "🐳 Laravel Containers:"
	@docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -E "(NAME|_php|nginx_shared)"

resources: ## Show resource usage
	@echo "📊 Resource Usage:"
	@docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}" | head -10

logs: ## Show logs for a project
	@if [ -z "$(PROJECT_NAME)" ]; then \
		echo "⚠️  Please specify PROJECT_NAME"; \
		echo "Usage: make logs PROJECT_NAME=<name>"; \
		exit 1; \
	fi; \
	echo "📋 Logs for $(PROJECT_NAME):"; \
	docker logs $(PROJECT_NAME)_php --tail 50
