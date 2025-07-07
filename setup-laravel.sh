#!/bin/bash

# Laravel Application Setup Script
# Handles Laravel installation, configuration, and initialization

set -e

# Input parameters
PROJECT_NAME=$1
PHP_CONTAINER=$2
CONTAINER_MOUNT_DIR=$3

# Validate input
if [ $# -ne 3 ]; then
    echo "Usage: $0 <project_name> <php_container> <container_mount_dir>"
    exit 1
fi

echo "🔧 Setting up Laravel application for $PROJECT_NAME..."

# Wait for containers to be ready with proper health check
echo "⏳ Waiting for containers to be ready..."
max_attempts=10
attempt=0

while [ $attempt -lt $max_attempts ]; do
    if docker exec ${PHP_CONTAINER} test -f ${CONTAINER_MOUNT_DIR}/artisan > /dev/null 2>&1; then
        echo "✅ Laravel application is ready"
        break
    fi
    echo "Waiting for Laravel installation... (attempt $((attempt + 1))/$max_attempts)"
    sleep 5
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
    
    # Clear all Laravel caches to ensure proper functionality
    echo "🧹 Clearing Laravel caches..."
    docker exec ${PHP_CONTAINER} php ${CONTAINER_MOUNT_DIR}/artisan optimize:clear > /dev/null 2>&1 || true
    echo "✅ Laravel caches cleared"
    
    # Restart PHP-FPM container to ensure clean state
    echo "🔄 Restarting PHP-FPM container..."
    docker restart ${PHP_CONTAINER} > /dev/null 2>&1
    echo "✅ PHP-FPM container restarted"
    
    echo "✅ Laravel application setup completed"
else
    echo "❌ Laravel installation verification failed"
    exit 1
fi 