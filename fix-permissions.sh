#!/bin/bash

# Fix File Permissions Script
# Ensures all project files are owned by Ubuntu default user (1000:1000)

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

PROJECT_NAME=$1
HOST_UID=${HOST_UID:-1000}
HOST_GID=${HOST_GID:-1000}

show_help() {
    echo "Fix File Permissions for Laravel Projects"
    echo "========================================"
    echo ""
    echo "Usage: $0 [project_name]"
    echo ""
    echo "Options:"
    echo "  project_name    Fix permissions for specific project (optional)"
    echo "  (no args)       Fix permissions for all projects"
    echo ""
    echo "Examples:"
    echo "  $0              # Fix all projects"
    echo "  $0 demo         # Fix demo project only"
    echo ""
    echo "This script ensures all files are owned by Ubuntu default user (UID:$HOST_UID, GID:$HOST_GID)"
}

fix_project_permissions() {
    local project=$1
    local project_path="/var/www/copilot-infra/$project"
    
    if [ ! -d "$project_path" ]; then
        echo -e "${RED}❌ Project directory not found: $project_path${NC}"
        return 1
    fi
    
    echo -e "${BLUE}🔧 Fixing permissions for project: $project${NC}"
    echo "   Path: $project_path"
    echo "   Setting ownership to UID:$HOST_UID, GID:$HOST_GID"
    
    # Fix ownership for all files
    sudo chown -R $HOST_UID:$HOST_GID "$project_path"
    
    # Set proper directory permissions
    sudo find "$project_path" -type d -exec chmod 755 {} \;
    
    # Set proper file permissions
    sudo find "$project_path" -type f -exec chmod 644 {} \;
    
    # Make specific files executable
    if [ -f "$project_path/artisan" ]; then
        sudo chmod 755 "$project_path/artisan"
    fi
    
    # Laravel storage and cache permissions
    if [ -d "$project_path/storage" ]; then
        sudo chmod -R 775 "$project_path/storage"
        sudo chown -R $HOST_UID:$HOST_GID "$project_path/storage"
    fi
    
    if [ -d "$project_path/bootstrap/cache" ]; then
        sudo chmod -R 775 "$project_path/bootstrap/cache"
        sudo chown -R $HOST_UID:$HOST_GID "$project_path/bootstrap/cache"
    fi
    
    # Fix container permissions if container is running
    local container_name="${project}_php"
    if docker ps --format "{{.Names}}" | grep -q "^${container_name}$"; then
        echo -e "${BLUE}🐳 Fixing container permissions for $container_name${NC}"
        docker exec "$container_name" chown -R $HOST_UID:$HOST_GID /var/www 2>/dev/null || true
        docker exec "$container_name" chmod -R 775 /var/www/storage 2>/dev/null || true
        docker exec "$container_name" chmod -R 775 /var/www/bootstrap/cache 2>/dev/null || true
    fi
    
    echo -e "${GREEN}✅ Permissions fixed for $project${NC}"
}

# Main execution
if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    show_help
    exit 0
fi

echo -e "${BLUE}🔧 Laravel File Permissions Fixer${NC}"
echo "=================================="
echo ""
echo "Ubuntu default user: $(whoami) (UID:$HOST_UID, GID:$HOST_GID)"
echo ""

if [ -n "$PROJECT_NAME" ]; then
    # Fix specific project
    fix_project_permissions "$PROJECT_NAME"
else
    # Fix all projects
    if [ ! -d "/var/www/copilot-infra" ]; then
        echo -e "${RED}❌ No projects directory found: /var/www/copilot-infra${NC}"
        exit 1
    fi
    
    projects=$(ls -1 /var/www/copilot-infra/ 2>/dev/null || echo "")
    
    if [ -z "$projects" ]; then
        echo -e "${YELLOW}⚠️  No projects found${NC}"
        exit 0
    fi
    
    echo -e "${BLUE}📋 Found projects: $projects${NC}"
    echo ""
    
    for project in $projects; do
        if [ -d "/var/www/copilot-infra/$project" ]; then
            fix_project_permissions "$project"
            echo ""
        fi
    done
fi

echo -e "${GREEN}🎉 File permissions fix completed!${NC}"
echo ""
echo -e "${BLUE}📝 You can now:${NC}"
echo "• Create files: touch /var/www/copilot-infra/PROJECT/newfile.txt"
echo "• Edit files: nano /var/www/copilot-infra/PROJECT/routes/web.php"
echo "• Modify Laravel: php artisan make:controller TestController"
echo "• All files will be owned by your Ubuntu user" 