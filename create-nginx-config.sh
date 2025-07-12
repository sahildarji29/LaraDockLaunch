#!/bin/bash

# Nginx Configuration Setup Script
# Creates nginx virtual host configuration for Laravel projects

set -e

# Input parameters
PROJECT_NAME=$1
VIRTUAL_HOST=$2
CONTAINER_MOUNT_DIR=$3
PHP_CONTAINER=$4
NGINX_CONFIG_DIR=${5:-/var/www/nginx-configs}

# Extract domain suffix from virtual host (e.g., "myapp.loc" -> "loc")
DOMAIN_SUFFIX=$(echo "$VIRTUAL_HOST" | sed 's/^[^.]*\.//')

if [ -z "$PROJECT_NAME" ]; then
    echo "Error: PROJECT_NAME is required"
    exit 1
fi

if [ -z "$VIRTUAL_HOST" ]; then
    echo "Error: VIRTUAL_HOST is required"
    exit 1
fi

if [ -z "$CONTAINER_MOUNT_DIR" ]; then
    echo "Error: CONTAINER_MOUNT_DIR is required"
    exit 1
fi

echo "🌐 Creating nginx configuration for $VIRTUAL_HOST..."

# Create nginx configuration directory if it doesn't exist
mkdir -p "$NGINX_CONFIG_DIR"

# Get the current nginx port from the shared container for display purposes
NGINX_PORT=80
if [ -f /tmp/laravel_nginx_port ]; then
    source /tmp/laravel_nginx_port
fi

# Create nginx configuration file
# Note: Inside the container, nginx always listens on port 80
# The external port mapping is handled by Docker
tee "$NGINX_CONFIG_DIR/${PROJECT_NAME}.conf" > /dev/null << EOF
server {
    listen 80;
    index index.php index.html;
    server_name ${VIRTUAL_HOST};

    root /var/www/${PROJECT_NAME}/public;

    # Security headers for production
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Referrer-Policy "no-referrer-when-downgrade" always;
    add_header Content-Security-Policy "default-src 'self' http: https: data: blob: 'unsafe-inline'" always;

    # Gzip compression for better performance
    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_types
        text/plain
        text/css
        text/xml
        text/javascript
        application/json
        application/javascript
        application/xml+rss
        application/atom+xml
        image/svg+xml;

    # Handle Laravel routing - more robust configuration
    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    # PHP processing with enhanced configuration
    location ~ \\.php\$ {
        include fastcgi_params;
        fastcgi_pass ${PHP_CONTAINER}:9000;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME /var/www/public\$fastcgi_script_name;
        fastcgi_param HTTP_PROXY "";
        fastcgi_intercept_errors off;
        fastcgi_buffer_size 16k;
        fastcgi_buffers 4 16k;
        fastcgi_connect_timeout 300;
        fastcgi_send_timeout 300;
        fastcgi_read_timeout 300;
        
        # Additional FastCGI parameters for Laravel
        fastcgi_param PATH_INFO \$fastcgi_path_info;
        fastcgi_param PATH_TRANSLATED \$document_root\$fastcgi_path_info;
    }

    # Deny access to hidden files
    location ~ /\\.ht {
        deny all;
    }

    # Deny access to sensitive files
    location ~ /\\.(env|git) {
        deny all;
    }

    # Enhanced static file handling with better caching
    location ~* \\.(jpg|jpeg|png|gif|ico|css|js|svg|woff|woff2|ttf|eot|webp|avif)\$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
        add_header Vary "Accept-Encoding";
        access_log off;
        try_files \$uri =404;
    }

    # Handle Laravel storage files (if needed)
    location /storage/ {
        alias /var/www/storage/app/public/;
        expires 1y;
        add_header Cache-Control "public, immutable";
        access_log off;
    }

    # Handle Laravel mix/vite assets
    location ~ ^/(build|assets)/ {
        expires 1y;
        add_header Cache-Control "public, immutable";
        access_log off;
    }

    # Handle favicon and robots.txt
    location = /favicon.ico {
        log_not_found off;
        access_log off;
    }

    location = /robots.txt {
        log_not_found off;
        access_log off;
    }

    # Logging for debugging
    access_log /var/log/nginx/${PROJECT_NAME}_access.log;
    error_log /var/log/nginx/${PROJECT_NAME}_error.log;
}
EOF

echo "✅ Nginx configuration created: $NGINX_CONFIG_DIR/${PROJECT_NAME}.conf"
echo "🌐 Virtual host will be accessible on port ${NGINX_PORT} (external)" 