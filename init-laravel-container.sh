#!/bin/bash

# Exit on any error
set -e

# Input parameters
PROJECT_NAME=$1
LOCAL_DIR=$2
VOLUME_NAME=$3

# Constants
CONTAINER_DIR="/var/www"
PHP_CONTAINER="${PROJECT_NAME}_php"
NGINX_CONTAINER="${PROJECT_NAME}_nginx"
PROXY_CONTAINER="laravel_proxy"
NETWORK_NAME="${PROJECT_NAME}_net"
PROXY_NETWORK="laravel_proxy_net"
PROJECT_PATH="$LOCAL_DIR/$PROJECT_NAME"
VIRTUAL_HOST="${PROJECT_NAME}.loc"

# Validate input
if [ $# -ne 3 ]; then
    echo "Usage: $0 <project_name> <local_dir> <volume_name>"
    exit 1
fi

# Check for required dependencies
command -v docker >/dev/null 2>&1 || { echo "❌ Docker is required but not installed."; exit 1; }
command -v docker-compose >/dev/null 2>&1 || { echo "❌ Docker Compose is required but not installed."; exit 1; }

# Check if Docker daemon is running
docker info >/dev/null 2>&1 || { echo "❌ Docker daemon is not running."; exit 1; }

echo "📦 Initializing Laravel container for project: $PROJECT_NAME"
echo "🌐 Virtual Host: $VIRTUAL_HOST"

# Create project directory if not exists
mkdir -p "$PROJECT_PATH"

# Create Docker volume if it doesn't exist, or remove and recreate if it exists
echo "🔄 Preparing Docker volume..."
if docker volume inspect $VOLUME_NAME > /dev/null 2>&1; then
    echo "📦 Removing existing volume to ensure clean installation..."
    docker volume rm $VOLUME_NAME --force 2>/dev/null || true
fi
docker volume create $VOLUME_NAME

# Create proxy network if it doesn't exist
echo "🌐 Setting up proxy network..."
if ! docker network inspect $PROXY_NETWORK > /dev/null 2>&1; then
    docker network create $PROXY_NETWORK
fi

# Create Dockerfile with Laravel installation capability
cat <<EOF > "$PROJECT_PATH/Dockerfile"
FROM php:8.3-fpm

RUN apt-get update && apt-get install -y \
    libzip-dev unzip curl git nginx supervisor && \
    docker-php-ext-install zip pdo pdo_mysql

COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

# Create a script to install Laravel if not already present
RUN echo '#!/bin/bash\n\
if [ ! -f "/var/www/artisan" ]; then\n\
    echo "Installing Laravel..."\n\
    cd /tmp\n\
    composer create-project laravel/laravel laravel-temp --no-interaction\n\
    if [ $? -eq 0 ]; then\n\
        echo "Moving Laravel files to /var/www..."\n\
        cp -r laravel-temp/. /var/www/\n\
        rm -rf laravel-temp\n\
        cd /var/www\n\
        chown -R www-data:www-data .\n\
        chmod -R 775 storage bootstrap/cache\n\
        cp .env.example .env\n\
        php artisan key:generate\n\
        echo "Laravel installation completed successfully."\n\
    else\n\
        echo "Laravel installation failed."\n\
        exit 1\n\
    fi\n\
else\n\
    echo "Laravel already installed."\n\
fi\n\
exec php-fpm' > /usr/local/bin/laravel-init.sh && chmod +x /usr/local/bin/laravel-init.sh

WORKDIR $CONTAINER_DIR

CMD ["/usr/local/bin/laravel-init.sh"]
EOF

# Create nginx.conf for the project
cat <<EOF > "$PROJECT_PATH/nginx.conf"
server {
    listen 80;
    index index.php index.html;
    server_name ${VIRTUAL_HOST};

    root $CONTAINER_DIR/public;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php$ {
        include fastcgi_params;
        fastcgi_pass ${PHP_CONTAINER}:9000;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOF

# Create docker-compose.yml
cat <<EOF > "$PROJECT_PATH/docker-compose.yml"
services:
  app:
    build:
      context: .
      dockerfile: Dockerfile
    container_name: ${PHP_CONTAINER}
    volumes:
      - ${VOLUME_NAME}:${CONTAINER_DIR}
    networks:
      - ${NETWORK_NAME}
      - ${PROXY_NETWORK}
    healthcheck:
      test: ["CMD", "php", "-v"]
      interval: 10s
      timeout: 5s
      retries: 5

  nginx:
    image: nginx:stable-alpine
    container_name: ${NGINX_CONTAINER}
    volumes:
      - ${VOLUME_NAME}:${CONTAINER_DIR}
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

volumes:
  ${VOLUME_NAME}:
EOF

# Start Laravel app container using Docker Compose
echo "🚀 Starting containers..."
docker-compose -p $PROJECT_NAME -f $PROJECT_PATH/docker-compose.yml up -d --build

# Setup or update the reverse proxy
echo "🔄 Setting up reverse proxy..."
setup_proxy() {
    # Check if proxy container exists
    if ! docker ps -a --format '{{.Names}}' | grep -q "^${PROXY_CONTAINER}$"; then
        echo "📦 Creating reverse proxy container..."
        docker run -d \
            --name $PROXY_CONTAINER \
            --restart unless-stopped \
            -p 80:80 \
            -v /var/run/docker.sock:/tmp/docker.sock:ro \
            --network $PROXY_NETWORK \
            nginxproxy/nginx-proxy:latest
    else
        echo "✅ Reverse proxy already exists"
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
    if docker exec ${PHP_CONTAINER} test -f ${CONTAINER_DIR}/artisan > /dev/null 2>&1; then
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
if docker exec ${PHP_CONTAINER} test -f ${CONTAINER_DIR}/artisan; then
    echo "✅ Laravel artisan found"
    
    # Check if we can run artisan commands
    if docker exec ${PHP_CONTAINER} php ${CONTAINER_DIR}/artisan --version > /dev/null 2>&1; then
        echo "✅ Laravel is working properly"
    else
        echo "⚠️  Laravel installed but artisan may have issues"
    fi
    
    # Show Laravel version
    LARAVEL_VERSION=$(docker exec ${PHP_CONTAINER} php ${CONTAINER_DIR}/artisan --version 2>/dev/null || echo "Unknown")
    echo "📋 $LARAVEL_VERSION"
else
    echo "❌ Laravel installation verification failed"
    exit 1
fi

echo ""
echo "🎉 Laravel project '$PROJECT_NAME' has been successfully initialized!"
echo "🌐 Virtual Host: $VIRTUAL_HOST"
echo "📁 Project files are stored in Docker volume: $VOLUME_NAME"
echo ""
echo "🔧 To access your application:"
echo "   1. Add this line to your /etc/hosts file:"
echo "      127.0.0.1 $VIRTUAL_HOST"
echo ""
echo "   2. Then visit: http://$VIRTUAL_HOST"
echo ""
echo "💡 Useful commands:"
echo "   - Access PHP container: docker exec -it ${PHP_CONTAINER} bash"
echo "   - View logs: docker logs ${PHP_CONTAINER}"
echo "   - Stop project: docker-compose -p $PROJECT_NAME -f $PROJECT_PATH/docker-compose.yml down"
