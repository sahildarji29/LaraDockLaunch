#!/bin/bash

# Laravel Container Initialization Script
# Main orchestration script for high-scale Laravel deployment

set -e

# Input parameters
PROJECT_NAME=$1
LOCAL_DIR=$2

# Constants
CONTAINER_DIR="/var/www/copilot-infra"
CONTAINER_MOUNT_DIR="/var/www"  # Path inside container where project is mounted
PHP_CONTAINER="${PROJECT_NAME}_php"
SHARED_NGINX_CONTAINER="laravel_nginx_shared"
SHARED_NETWORK="laravel_shared_net"
PROJECT_PATH="$LOCAL_DIR/$PROJECT_NAME"
MASTER_IMAGE="laravel-master:latest"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NGINX_CONFIG_DIR="/var/www/nginx-configs"
PROJECT_VOLUME="${PROJECT_NAME}_data"

# Domain configuration
DOMAIN=${DOMAIN:-"loc"}  # Default domain is 'loc'

# Set virtual host
VIRTUAL_HOST="${PROJECT_NAME}.${DOMAIN}"

# Function to find available port for shared nginx (only needed once)
find_available_port() {
    for port in {80..90}; do
        # Check if port is already in use by any process
        if ! ss -tuln 2>/dev/null | grep -q ":$port " && ! netstat -tuln 2>/dev/null | grep -q ":$port "; then
            # Check if port is already used by Docker containers
            if ! docker ps --format "table {{.Ports}}" 2>/dev/null | grep -q ":$port->"; then
                # Double-check by trying to bind to the port
                if timeout 1 bash -c "</dev/tcp/127.0.0.1/$port" 2>/dev/null; then
                    continue  # Port is in use
                else
                    echo $port
                    return 0
                fi
            fi
        fi
    done
    # Fallback to port 8080 if no port in 80-90 range is available
    echo 8080
}

# Function to automatically fix file permissions for new projects
fix_project_permissions_auto() {
    local project_name=$1
    local project_path=$2
    local host_uid=$(id -u)
    local host_gid=$(id -g)
    
    echo "   🔧 Setting ownership to Ubuntu user (UID:$host_uid, GID:$host_gid)"
    echo "   📁 Project path: $project_path"
    
    # Fix ownership for all files using current user (no sudo needed during init)
    chown -R $host_uid:$host_gid "$project_path" 2>/dev/null || {
        echo "   ⚠️  Note: Some files may require sudo for permission changes later"
        echo "   💡 Run 'make fix-permissions PROJECT_NAME=$project_name' if needed"
    }
    
    # Set proper directory permissions
    find "$project_path" -type d -exec chmod 755 {} \; 2>/dev/null || true
    
    # Set proper file permissions
    find "$project_path" -type f -exec chmod 644 {} \; 2>/dev/null || true
    
    # Make specific files executable
    if [ -f "$project_path/artisan" ]; then
        chmod 755 "$project_path/artisan" 2>/dev/null || true
    fi
    
    # Laravel storage and cache permissions
    if [ -d "$project_path/storage" ]; then
        chmod -R 775 "$project_path/storage" 2>/dev/null || true
        chown -R $host_uid:$host_gid "$project_path/storage" 2>/dev/null || true
    fi
    
    if [ -d "$project_path/bootstrap/cache" ]; then
        chmod -R 775 "$project_path/bootstrap/cache" 2>/dev/null || true
        chown -R $host_uid:$host_gid "$project_path/bootstrap/cache" 2>/dev/null || true
    fi
    
    # Fix container permissions if container is running
    local container_name="${project_name}_php"
    if docker ps --format "{{.Names}}" | grep -q "^${container_name}$"; then
        echo "   🐳 Syncing container permissions..."
        docker exec "$container_name" chown -R $host_uid:$host_gid /var/www 2>/dev/null || true
        docker exec "$container_name" chmod -R 775 /var/www/storage 2>/dev/null || true
        docker exec "$container_name" chmod -R 775 /var/www/bootstrap/cache 2>/dev/null || true
    fi
    
    echo "   ✅ File permissions configured for Ubuntu user"
}

# Validate input
if [ $# -ne 2 ]; then
    echo "Usage: $0 <project_name> <local_dir>"
    exit 1
fi

# Check for required dependencies
command -v docker >/dev/null 2>&1 || { echo "❌ Docker is required but not installed."; exit 1; }
command -v docker-compose >/dev/null 2>&1 || { echo "❌ Docker Compose is required but not installed."; exit 1; }

# Check if Docker daemon is running
docker info >/dev/null 2>&1 || { echo "❌ Docker daemon is not running."; exit 1; }

# Check if user is in docker group
if ! groups | grep -q docker; then
    echo "❌ Current user is not in the docker group. Please run:"
    echo "   sudo usermod -aG docker $USER"
    echo "   Then log out and log back in, or run: newgrp docker"
    exit 1
fi

echo "📦 Initializing Laravel container for project: $PROJECT_NAME"
echo "🌐 Virtual Host: $VIRTUAL_HOST"
echo "🏗️  High-Scale Architecture: Shared Nginx + Individual PHP-FPM"

# Build master image if it doesn't exist
build_master_image() {
    echo "🔍 Checking for master Laravel image..."
    
    if ! docker images --format "{{.Repository}}:{{.Tag}}" | grep -q "^$MASTER_IMAGE$"; then
        echo "🏗️  Master image not found. Building master Laravel 12 image with Node.js support..."
        echo "⏳ This is a one-time process and may take a few minutes..."
        
        if [ -f "$SCRIPT_DIR/Dockerfile.master" ]; then
            docker build -f "$SCRIPT_DIR/Dockerfile.master" -t "$MASTER_IMAGE" "$SCRIPT_DIR"
            echo "✅ Master image '$MASTER_IMAGE' built successfully!"
        else
            echo "❌ Dockerfile.master not found in $SCRIPT_DIR"
            exit 1
        fi
    else
        echo "✅ Master image '$MASTER_IMAGE' already exists"
    fi
}

# Setup base directories
setup_base_directories() {
    echo "🏗️  Setting up base directories..."
    
    # Create base copilot-infra directory if not exists
    if [ ! -d "$LOCAL_DIR" ]; then
        echo "🏗️  Creating base directory: $LOCAL_DIR"
        mkdir -p "$LOCAL_DIR"
        echo "✅ Base directory created"
    fi

    # Create nginx configs directory if not exists
    if [ ! -d "$NGINX_CONFIG_DIR" ]; then
        echo "🏗️  Creating nginx configs directory: $NGINX_CONFIG_DIR"
        mkdir -p "$NGINX_CONFIG_DIR"
        echo "✅ Nginx configs directory created"
    fi

    # Create project directory if not exists
    echo "📁 Creating project directory: $PROJECT_PATH"
    mkdir -p "$PROJECT_PATH"

    echo "ℹ️  Laravel will be installed automatically by the container on first run"
}

# Setup shared network
setup_shared_network() {
    echo "🌐 Setting up shared network..."
    if ! docker network inspect $SHARED_NETWORK > /dev/null 2>&1; then
        docker network create $SHARED_NETWORK
        echo "✅ Shared network '$SHARED_NETWORK' created"
    else
        echo "✅ Shared network '$SHARED_NETWORK' already exists"
    fi
}

# Create logs volume for data persistence
create_volumes() {
    echo "💾 Creating logs volume..."
    
    # Create logs volume only (data is now bind mounted)
    LOGS_VOLUME="${PROJECT_NAME}_logs"
    if ! docker volume ls --format "{{.Name}}" | grep -q "^$LOGS_VOLUME$"; then
        docker volume create $LOGS_VOLUME
        echo "✅ Logs volume '$LOGS_VOLUME' created"
    else
        echo "✅ Logs volume '$LOGS_VOLUME' already exists"
    fi
}

# Main execution flow
main() {
    echo "🚀 Starting Laravel container initialization..."
    
    # Step 1: Build master image
    build_master_image
    
    # Step 2: Setup base directories
    setup_base_directories
    
    # Step 3: Setup shared network
    setup_shared_network
    
    # Step 4: Create nginx configuration
    echo "🌐 Creating nginx configuration..."
    "$SCRIPT_DIR/create-nginx-config.sh" "$PROJECT_NAME" "$VIRTUAL_HOST" "$CONTAINER_MOUNT_DIR" "$PHP_CONTAINER" "$NGINX_CONFIG_DIR"
    
    # Step 5: Create Docker Compose configuration
    echo "🐳 Creating Docker Compose configuration..."
    "$SCRIPT_DIR/create-docker-compose.sh" "$PROJECT_NAME" "$PROJECT_PATH" "$MASTER_IMAGE" "$PHP_CONTAINER" "$SHARED_NETWORK" "$PROJECT_VOLUME" "$CONTAINER_MOUNT_DIR"
    
    # Step 6: Create named volumes
    create_volumes
    
    # Step 7: Start PHP-FPM container
    echo "🚀 Starting PHP-FPM container..."
    cd "$PROJECT_PATH"
    export HOST_UID=$(id -u)
    export HOST_GID=$(id -g)
    docker-compose -p $PROJECT_NAME -f $PROJECT_PATH/docker-compose.yml up -d
    
    # Wait for container to be healthy before reloading nginx
    echo "⏳ Waiting for container to be healthy..."
    local max_attempts=30
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        if docker ps --format "table {{.Names}}\t{{.Status}}" | grep -q "$PROJECT_NAME_php.*healthy"; then
            echo "✅ Container is healthy"
            break
        elif docker ps --format "table {{.Names}}\t{{.Status}}" | grep -q "$PROJECT_NAME_php.*unhealthy"; then
            echo "❌ Container is unhealthy, checking logs..."
            docker logs "$PROJECT_NAME_php" --tail 10
            return 1
        else
            echo "⏳ Waiting for container health... (attempt $attempt/$max_attempts)"
            sleep 10
            attempt=$((attempt + 1))
        fi
    done
    
    if [ $attempt -gt $max_attempts ]; then
        echo "❌ Container did not become healthy within expected time"
        return 1
    fi
    
    # Step 8: Setup shared nginx container
    echo "🌐 Setting up shared nginx container..."
    "$SCRIPT_DIR/setup-shared-nginx.sh" "$SHARED_NGINX_CONTAINER" "$NGINX_CONFIG_DIR" "$SHARED_NETWORK"
    
    # Step 8.5: Direct container access information
    echo "🌐 Container nginx access information..."
    if [ -f /tmp/laravel_nginx_port ]; then
        source /tmp/laravel_nginx_port
        echo "✅ Shared nginx container running on port $NGINX_PORT"
        echo "🔗 Direct access: http://project.domain:$NGINX_PORT"
        echo "💡 For clean URLs, add to /etc/hosts: 127.0.0.1 project.domain"
    else
        echo "⚠️  Port information not available"
    fi
    
    # Step 9: Setup Laravel application
    echo "🔧 Setting up Laravel application..."
    "$SCRIPT_DIR/setup-laravel.sh" "$PROJECT_NAME" "$PHP_CONTAINER" "$CONTAINER_MOUNT_DIR"
    
    # Step 9.5: Automatically fix file permissions for Ubuntu user
    echo "🔒 Setting correct file permissions for Ubuntu user..."
    fix_project_permissions_auto "$PROJECT_NAME" "$PROJECT_PATH"
    
    # Step 10: Reload nginx configuration to ensure new project is active
    echo "🔄 Reloading nginx configuration..."
    if docker ps --format "{{.Names}}" | grep -q "^${SHARED_NGINX_CONTAINER}$"; then
        docker exec ${SHARED_NGINX_CONTAINER} nginx -s reload > /dev/null 2>&1 || true
        echo "✅ Nginx configuration reloaded"
    else
        echo "⚠️  Shared nginx container not found, skipping reload"
    fi
    
    # Step 11: Update nginx configuration to use port 80 (internal)
    echo "🔄 Updating nginx configuration to use port 80 (internal)..."
    if [ -f "$NGINX_CONFIG_DIR/${PROJECT_NAME}.conf" ]; then
        sed -i "s/listen [0-9]*;/listen 80;/" "$NGINX_CONFIG_DIR/${PROJECT_NAME}.conf"
        echo "✅ Updated nginx configuration to use port 80 (internal)"
    fi
    
    # Step 12: Display success message
    display_success_message
}

# Display success message
display_success_message() {
    # Get the nginx port for final output
    if [ -f /tmp/laravel_nginx_port ]; then
        source /tmp/laravel_nginx_port
    else
        NGINX_PORT=80  # fallback
    fi
    
    echo ""
    echo "🎉 Laravel project '$PROJECT_NAME' has been successfully initialized!"
    echo "🌐 Virtual Host: $VIRTUAL_HOST"
    echo "🚀 Shared Nginx Port: $NGINX_PORT"
    echo "📁 Project files are in local directory: $PROJECT_PATH"
    echo "⚙️  Architecture: Shared Nginx + Individual PHP-FPM"
    echo "💾 Data Persistence: Bind mount to local filesystem"
    echo "🔧 Resource Limits: 256MB RAM, 0.5 CPU per container"
    echo "🔒 File Permissions: Automatically configured for Ubuntu user"
    echo "📝 Configuration: $NGINX_CONFIG_DIR/${PROJECT_NAME}.conf"
    echo ""
    echo "🔧 To access your application:"
    echo "   1. Direct access: http://localhost:$NGINX_PORT"
    echo "   2. With domain: Add to /etc/hosts: 127.0.0.1 $VIRTUAL_HOST"
    echo "   3. Visit: http://$VIRTUAL_HOST:$NGINX_PORT"
    echo "   4. Configure SSL certificate for HTTPS if needed"
    echo ""
    echo "📊 High-Scale Deployment Benefits:"
    echo "   • 50% fewer containers (1 shared nginx vs per-project nginx)"
    echo "   • Single shared network reduces overhead"
    echo "   • Named volumes ensure data persistence"
    echo "   • Resource limits prevent resource exhaustion"
    echo "   • Optimized nginx configuration for performance"
    echo "   • File permissions automatically configured (no manual fix needed)"
    echo "   • Direct container access (no sudo required for setup)"
}

# Run main function
main
