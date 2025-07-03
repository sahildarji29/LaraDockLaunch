#!/bin/bash

# Exit on any error
set -e

# Input parameters
PROJECT_NAME=$1
LOCAL_DIR=$2

# Constants
CONTAINER_DIR="/var/www/copilot-infra"
CONTAINER_MOUNT_DIR="/var/www"  # Path inside container where project is mounted
PHP_CONTAINER="${PROJECT_NAME}_php"
NGINX_CONTAINER="${PROJECT_NAME}_nginx"
PROXY_CONTAINER="laravel_proxy"
NETWORK_NAME="${PROJECT_NAME}_net"
PROXY_NETWORK="laravel_proxy_net"
PROJECT_PATH="$LOCAL_DIR/$PROJECT_NAME"
MASTER_IMAGE="laravel-master:latest"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Domain configuration
DOMAIN=${DOMAIN:-"loc"}  # Default domain is 'loc'

# Set virtual host
VIRTUAL_HOST="${PROJECT_NAME}.${DOMAIN}"

# Function to find available port in 80-90 range
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

echo "📦 Initializing Laravel container for project: $PROJECT_NAME"
echo "🌐 Virtual Host: $VIRTUAL_HOST"

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

build_master_image

# Create base copilot-infra directory with www-data ownership if not exists
if [ ! -d "$LOCAL_DIR" ]; then
    echo "🏗️  Creating base directory: $LOCAL_DIR"
    sudo mkdir -p "$LOCAL_DIR"
    sudo chown www-data:www-data "$LOCAL_DIR"
    sudo chmod 755 "$LOCAL_DIR"
    echo "✅ Base directory created with www-data ownership"
fi

# Create project directory if not exists
echo "📁 Creating project directory: $PROJECT_PATH"
sudo mkdir -p "$PROJECT_PATH"
sudo chown www-data:www-data "$PROJECT_PATH"
sudo chmod 755 "$PROJECT_PATH"

echo "ℹ️  Laravel will be installed automatically by the container on first run"

# Create proxy network if it doesn't exist
echo "🌐 Setting up proxy network..."
if ! docker network inspect $PROXY_NETWORK > /dev/null 2>&1; then
    docker network create $PROXY_NETWORK
fi

# Create nginx.conf for the project
sudo tee "$PROJECT_PATH/nginx.conf" > /dev/null <<EOF
server {
    listen 80;
    index index.php index.html;
    server_name ${VIRTUAL_HOST};

    root $CONTAINER_MOUNT_DIR/public;

    # Security headers for production
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Referrer-Policy "no-referrer-when-downgrade" always;
    add_header Content-Security-Policy "default-src 'self' http: https: data: blob: 'unsafe-inline'" always;

    # Handle Laravel routing
    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    # PHP processing
    location ~ \.php$ {
        include fastcgi_params;
        fastcgi_pass ${PHP_CONTAINER}:9000;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param HTTP_PROXY "";
        fastcgi_intercept_errors off;
        fastcgi_buffer_size 16k;
        fastcgi_buffers 4 16k;
        fastcgi_connect_timeout 300;
        fastcgi_send_timeout 300;
        fastcgi_read_timeout 300;
    }

    # Deny access to hidden files
    location ~ /\.ht {
        deny all;
    }

    # Deny access to sensitive files
    location ~ /\.(env|git) {
        deny all;
    }

    # Static file caching for production
    location ~* \.(jpg|jpeg|png|gif|ico|css|js|svg|woff|woff2|ttf|eot)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
        access_log off;
    }
}
EOF

# Set ownership for nginx.conf
sudo chown www-data:www-data "$PROJECT_PATH/nginx.conf"
sudo chmod 644 "$PROJECT_PATH/nginx.conf"

# Create docker-compose.yml using master image
sudo tee "$PROJECT_PATH/docker-compose.yml" > /dev/null <<EOF
services:
  app:
    image: ${MASTER_IMAGE}
    container_name: ${PHP_CONTAINER}
    volumes:
      - ./:${CONTAINER_MOUNT_DIR}
    networks:
      - ${NETWORK_NAME}
      - ${PROXY_NETWORK}
    environment:
      - PROJECT_NAME=${PROJECT_NAME}
      - CONTAINER_MOUNT_DIR=${CONTAINER_MOUNT_DIR}
    healthcheck:
      test: ["CMD", "php", "-v"]
      interval: 10s
      timeout: 5s
      retries: 5

  nginx:
    image: nginx:stable-alpine
    container_name: ${NGINX_CONTAINER}
    volumes:
      - ./:${CONTAINER_MOUNT_DIR}
      - ./nginx.conf:/etc/nginx/conf.d/default.conf
    depends_on:
      app:
        condition: service_healthy
    networks:
      - ${NETWORK_NAME}
      - ${PROXY_NETWORK}
    environment:
      - VIRTUAL_HOST=${VIRTUAL_HOST}

networks:
  ${NETWORK_NAME}:
    driver: bridge
  ${PROXY_NETWORK}:
    external: true
EOF

# Set ownership for docker-compose.yml
sudo chown www-data:www-data "$PROJECT_PATH/docker-compose.yml"
sudo chmod 644 "$PROJECT_PATH/docker-compose.yml"

# Start Laravel app container using Docker Compose
echo "🚀 Starting containers using master image..."
docker-compose -p $PROJECT_NAME -f $PROJECT_PATH/docker-compose.yml up -d

# Setup or update the reverse proxy
echo "🔄 Setting up reverse proxy..."
setup_proxy() {
    # Check if proxy container exists
    if ! docker ps -a --format '{{.Names}}' | grep -q "^${PROXY_CONTAINER}$"; then
        # Find available port
        PROXY_PORT=$(find_available_port)
        echo "📦 Creating reverse proxy container on port $PROXY_PORT..."
        
        docker run -d \
            --name $PROXY_CONTAINER \
            --restart unless-stopped \
            -p $PROXY_PORT:80 \
            -v /var/run/docker.sock:/tmp/docker.sock:ro \
            --network $PROXY_NETWORK \
            nginxproxy/nginx-proxy:latest
        
        # Store the port for future reference
        echo "PROXY_PORT=$PROXY_PORT" > /tmp/laravel_proxy_port
        echo "✅ Reverse proxy created on port $PROXY_PORT"
    else
        echo "✅ Reverse proxy already exists"
        # Get the existing port
        PROXY_PORT=$(docker port $PROXY_CONTAINER 80/tcp 2>/dev/null | cut -d':' -f2)
        if [ -z "$PROXY_PORT" ]; then
            PROXY_PORT=80  # fallback
        fi
        echo "PROXY_PORT=$PROXY_PORT" > /tmp/laravel_proxy_port
        
        # Ensure it's running
        if ! docker ps --format '{{.Names}}' | grep -q "^${PROXY_CONTAINER}$"; then
            echo "🔄 Starting existing reverse proxy..."
            docker start $PROXY_CONTAINER
        fi
    fi
}

setup_proxy

# Wait for containers to be ready with proper health check
echo "⏳ Waiting for containers to be ready..."
max_attempts=5
attempt=0

while [ $attempt -lt $max_attempts ]; do
    if docker exec ${PHP_CONTAINER} test -f ${CONTAINER_MOUNT_DIR}/artisan > /dev/null 2>&1; then
        echo "✅ Laravel application is ready"
        break
    fi
    echo "Waiting for Laravel installation... (attempt $((attempt + 1))/$max_attempts)"
    sleep 3
    attempt=$((attempt + 1))
done

if [ $attempt -eq $max_attempts ]; then
    echo "❌ Laravel installation failed or took too long"
    echo "📋 Container logs:"
    docker logs ${PHP_CONTAINER} --tail 20
    exit 1
fi

# Verify Laravel installation
echo "🔍 Verifying Laravel installation..."
if docker exec ${PHP_CONTAINER} test -f ${CONTAINER_MOUNT_DIR}/artisan; then
    echo "✅ Laravel artisan found"
    
    # Setup Laravel environment
    echo "🔧 Setting up Laravel environment..."
    
    # Ensure .env file exists
    if ! docker exec ${PHP_CONTAINER} test -f ${CONTAINER_MOUNT_DIR}/.env; then
        echo "📄 Creating .env file from .env.example..."
        docker exec ${PHP_CONTAINER} cp ${CONTAINER_MOUNT_DIR}/.env.example ${CONTAINER_MOUNT_DIR}/.env
    fi
    
    # Generate application key
    echo "🔑 Generating Laravel application key..."
    if docker exec ${PHP_CONTAINER} php ${CONTAINER_MOUNT_DIR}/artisan key:generate --force; then
        echo "✅ Application key generated successfully"
    else
        echo "⚠️  Failed to generate application key"
    fi
    
    # Run database migrations
    echo "🗃️  Running database migrations..."
    if docker exec ${PHP_CONTAINER} php ${CONTAINER_MOUNT_DIR}/artisan migrate --force; then
        echo "✅ Database migrations completed successfully"
    else
        echo "⚠️  Database migrations failed (this is normal if no database is configured)"
    fi
    
    # Set proper permissions
    echo "🔒 Setting proper file permissions..."
    docker exec ${PHP_CONTAINER} chown -R www-data:www-data ${CONTAINER_MOUNT_DIR}
    docker exec ${PHP_CONTAINER} chmod -R 775 ${CONTAINER_MOUNT_DIR}/storage ${CONTAINER_MOUNT_DIR}/bootstrap/cache 2>/dev/null || true
    
    # Check if we can run artisan commands
    if docker exec ${PHP_CONTAINER} php ${CONTAINER_MOUNT_DIR}/artisan --version > /dev/null 2>&1; then
        echo "✅ Laravel is working properly"
    else
        echo "⚠️  Laravel installed but artisan may have issues"
    fi
    
    # Show Laravel version
    LARAVEL_VERSION=$(docker exec ${PHP_CONTAINER} php ${CONTAINER_MOUNT_DIR}/artisan --version 2>/dev/null || echo "Unknown")
    echo "📋 $LARAVEL_VERSION"
else
    echo "❌ Laravel installation verification failed"
    exit 1
fi

# Get the proxy port for final output
if [ -f /tmp/laravel_proxy_port ]; then
    source /tmp/laravel_proxy_port
else
    PROXY_PORT=80  # fallback
fi

echo ""
echo "🎉 Laravel project '$PROJECT_NAME' has been successfully initialized!"
echo "🌐 Virtual Host: $VIRTUAL_HOST"
echo "🚀 Proxy Port: $PROXY_PORT"
echo "📁 Project files are accessible at: $PROJECT_PATH"
echo "👤 Files owned by: www-data:www-data"
echo "📝 You can now edit Laravel files directly in: $PROJECT_PATH"
echo "🟢 Node.js and npm are available in the container for frontend development"
echo ""
echo "🔧 To access your application:"
echo "   1. Ensure DNS points $VIRTUAL_HOST to this server"
if [ -f /tmp/laravel_proxy_port ]; then
    source /tmp/laravel_proxy_port
    if [ "$PROXY_PORT" = "80" ]; then
        echo "   2. Visit: http://$VIRTUAL_HOST"
    else
        echo "   2. Visit: http://$VIRTUAL_HOST:$PROXY_PORT"
    fi
else
    echo "   2. Visit: http://$VIRTUAL_HOST"
fi
echo "   3. Configure SSL certificate for HTTPS if needed"
