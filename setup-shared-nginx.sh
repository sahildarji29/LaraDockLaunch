#!/bin/bash

# Shared Nginx Container Setup Script
# Creates and manages the shared nginx container for all Laravel projects

set -e

# Input parameters
SHARED_NGINX_CONTAINER=$1
NGINX_CONFIG_DIR=$2
SHARED_NETWORK=$3

# Validate input
if [ $# -ne 3 ]; then
    echo "Usage: $0 <shared_nginx_container> <nginx_config_dir> <shared_network>"
    exit 1
fi

# Function to find available port for shared nginx
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

echo "🔄 Setting up shared nginx container..."

# Remove existing container if it exists (to update mounts)
if docker ps -a --format '{{.Names}}' | grep -q "^${SHARED_NGINX_CONTAINER}$"; then
    echo "🗑️  Removing old shared nginx container to update mounts..."
    docker rm -f $SHARED_NGINX_CONTAINER
fi

# Find available port for shared nginx
NGINX_PORT=$(find_available_port)
echo "📦 Creating shared nginx container on port $NGINX_PORT..."

# Create nginx main configuration in a separate directory
mkdir -p "$NGINX_CONFIG_DIR/main"
tee "$NGINX_CONFIG_DIR/main/nginx.conf" > /dev/null <<EOF
user nginx;
worker_processes auto;
pid /run/nginx.pid;

events {
    worker_connections 2048;
    use epoll;
    multi_accept on;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    # Performance optimizations
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;
    client_max_body_size 100M;

    # Gzip compression
    gzip on;
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_types text/plain text/css application/json application/javascript text/xml application/xml application/xml+rss text/javascript;

    # Security headers
    server_tokens off;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;

    # Logging
    log_format main '\$remote_addr - \$remote_user [\$time_local] "\$request" '
                    '\$status \$body_bytes_sent "\$http_referer" '
                    '"\$http_user_agent" "\$http_x_forwarded_for"';
    
    access_log /var/log/nginx/access.log main;
    error_log /var/log/nginx/error.log;

    # Include all project configurations
    include /etc/nginx/conf.d/*.conf;
}
EOF

# Find all PHP containers and mount their local project directories (bind mounts)
VOLUME_MOUNTS=""
for php_container in $(docker ps -a --format '{{.Names}}' | grep _php); do
    project=$(echo "$php_container" | sed 's/_php$//')
    
    # Get the bind mount source path for /var/www
    bind_mount_source=$(docker inspect $php_container --format '{{range .Mounts}}{{if eq .Destination "/var/www"}}{{.Source}}{{end}}{{end}}')
    
    if [ -n "$bind_mount_source" ] && [ -d "$bind_mount_source" ]; then
        echo "📁 Mounting project directory for $project: $bind_mount_source"
        VOLUME_MOUNTS="$VOLUME_MOUNTS -v $bind_mount_source:/var/www/$project:ro"
    else
        echo "⚠️  No bind mount found for $project, checking for legacy volume..."
        # Fallback: check for legacy Docker volume (for backward compatibility)
        data_volume=$(docker inspect $php_container --format '{{range .Mounts}}{{if eq .Destination "/var/www"}}{{.Name}}{{end}}{{end}}')
        if [ -n "$data_volume" ]; then
            echo "📦 Mounting legacy volume for $project: $data_volume"
            VOLUME_MOUNTS="$VOLUME_MOUNTS -v $data_volume:/var/www/$project:ro"
        else
            echo "❌ No mount found for $project, skipping..."
        fi
    fi
done

docker run -d \
    --name $SHARED_NGINX_CONTAINER \
    --restart unless-stopped \
    -p $NGINX_PORT:80 \
    -v "$NGINX_CONFIG_DIR:/etc/nginx/conf.d" \
    -v "$NGINX_CONFIG_DIR/main/nginx.conf:/etc/nginx/nginx.conf" \
    $VOLUME_MOUNTS \
    --network $SHARED_NETWORK \
    nginx:stable-alpine

# Store the port for future reference
echo "NGINX_PORT=$NGINX_PORT" > /tmp/laravel_nginx_port
echo "✅ Shared nginx container created on port $NGINX_PORT"

echo "✅ Shared nginx container setup completed" 