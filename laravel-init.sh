#!/bin/bash
PROJECT_NAME=${PROJECT_NAME:-laravel-app}
CONTAINER_MOUNT_DIR=${CONTAINER_MOUNT_DIR:-/var/www}
HOST_UID=${HOST_UID:-1000}
HOST_GID=${HOST_GID:-1000}
APP_USER=www-data

echo "🚀 Starting Laravel container: $PROJECT_NAME"
echo "📁 Mount directory: $CONTAINER_MOUNT_DIR"
echo "⚙️  High-Scale Mode: Resource-optimized"
echo "👤 Host UID: $HOST_UID, Host GID: $HOST_GID"

# Dynamic user setup - run as root initially
if [ "$(id -u)" = "0" ]; then
    echo "🔧 Setting up dynamic user permissions for Ubuntu default user..."
    
    # Update www-data user and group to match host UID/GID
    echo "🔄 Updating www-data to match Ubuntu user (UID:$HOST_UID, GID:$HOST_GID)"
    
    # Update group GID
    groupmod -g $HOST_GID $APP_USER
    
    # Update user UID and ensure it's in the correct group
    usermod -u $HOST_UID -g $APP_USER $APP_USER
    
    # Fix volume permissions to match host user - ensure all files are owned by host user
    echo "🔒 Setting correct ownership for Ubuntu user (UID:$HOST_UID, GID:$HOST_GID)..."
    chown -R $HOST_UID:$HOST_GID "$CONTAINER_MOUNT_DIR"
    chmod -R 755 "$CONTAINER_MOUNT_DIR"
    
    # Ensure storage and cache directories have proper permissions for Laravel
    if [ -d "$CONTAINER_MOUNT_DIR/storage" ]; then
        chmod -R 775 "$CONTAINER_MOUNT_DIR/storage"
        chown -R $HOST_UID:$HOST_GID "$CONTAINER_MOUNT_DIR/storage"
    fi
    
    if [ -d "$CONTAINER_MOUNT_DIR/bootstrap/cache" ]; then
        chmod -R 775 "$CONTAINER_MOUNT_DIR/bootstrap/cache"
        chown -R $HOST_UID:$HOST_GID "$CONTAINER_MOUNT_DIR/bootstrap/cache"
    fi
    
    # Create necessary directories with correct ownership
    mkdir -p "$CONTAINER_MOUNT_DIR/storage/logs" "$CONTAINER_MOUNT_DIR/storage/framework/cache" "$CONTAINER_MOUNT_DIR/storage/framework/sessions" "$CONTAINER_MOUNT_DIR/storage/framework/views"
    chown -R $HOST_UID:$HOST_GID "$CONTAINER_MOUNT_DIR/storage"
    chmod -R 775 "$CONTAINER_MOUNT_DIR/storage"
    
    # Switch to the dynamic user for the rest of the script
    echo "🔄 Switching to Ubuntu user $APP_USER (UID:$HOST_UID)..."
    exec su-exec $APP_USER "$0" "$@"
fi

# Display Node.js information
echo "🟢 Node.js version: $(node --version 2>/dev/null || echo "Not available")"
echo "📦 NPM version: $(npm --version 2>/dev/null || echo "Not available")"
echo "🔧 PHP Memory Limit: $(php -r 'echo ini_get("memory_limit");')"
echo "⚡ OPcache: $(php -r 'echo ini_get("opcache.enable") ? "Enabled" : "Disabled";')"

# Check if Laravel project exists, if not create it
if [ ! -f "$CONTAINER_MOUNT_DIR/artisan" ]; then
    echo "📦 Creating new Laravel 12 project in $CONTAINER_MOUNT_DIR..."
    cd /tmp
    composer create-project laravel/laravel laravel-temp --prefer-dist --no-dev
    cp -r laravel-temp/* "$CONTAINER_MOUNT_DIR/"
    cp laravel-temp/.env.example "$CONTAINER_MOUNT_DIR/" 2>/dev/null || true
    cp laravel-temp/.gitignore "$CONTAINER_MOUNT_DIR/" 2>/dev/null || true
    rm -rf laravel-temp
    cd "$CONTAINER_MOUNT_DIR"
    echo "✅ Laravel 12 project created successfully"
else
    echo "✅ Laravel project already exists"
    cd "$CONTAINER_MOUNT_DIR"
fi

# Setup Laravel environment
if [ -f ".env.example" ] && [ ! -f ".env" ]; then
    echo "📄 Setting up .env file..."
    cp .env.example .env
fi

# Generate application key if not exists
if ! grep -q "APP_KEY=base64:" .env 2>/dev/null; then
    echo "🔑 Generating Laravel application key..."
    php artisan key:generate --force
fi

# Install npm dependencies and build assets if package.json exists
# Skip npm for initial startup to get PHP-FPM running quickly
if [ -f "package.json" ] && [ "${SKIP_NPM:-false}" != "true" ]; then
    echo "📦 Installing npm dependencies..."
    # Use timeout to prevent hanging
    timeout 300 npm install || {
        echo "⚠️  NPM install timed out or failed, continuing without frontend assets..."
        echo "📦 You can run 'npm install && npm run build' manually later if needed"
    }
    
    if [ -f "node_modules/.bin/vite" ] || [ -f "node_modules/.bin/webpack" ]; then
        echo "🏗️ Building assets..."
        timeout 300 npm run build || {
            echo "⚠️  Asset build failed, continuing without built assets..."
        }
        echo "✅ Assets built successfully"
    fi
    
    # Clean npm cache to save space
    npm cache clean --force 2>/dev/null || true
else
    echo "⏭️  Skipping npm installation for quick startup"
    echo "📦 Run 'docker exec ${PROJECT_NAME}_php npm install && npm run build' manually if needed"
fi

# Run database migrations
echo "🗄️ Running database migrations..."
php artisan migrate --force
echo "✅ Database migrations completed"

# Set proper permissions
echo "🔒 Setting proper file permissions..."
chown -R $HOST_UID:$HOST_GID "$CONTAINER_MOUNT_DIR"
chmod -R 755 "$CONTAINER_MOUNT_DIR"
chmod -R 775 "$CONTAINER_MOUNT_DIR/storage" "$CONTAINER_MOUNT_DIR/bootstrap/cache" 2>/dev/null || true

# Optimize Laravel for production
echo "⚡ Optimizing Laravel for high-scale deployment..."
php artisan config:cache
php artisan route:cache
php artisan view:cache

echo "✅ Laravel container $PROJECT_NAME is ready!"
echo "📊 Memory usage: $(free -m | grep Mem | awk '{print $3}'MB)/$(free -m | grep Mem | awk '{print $2}'MB)"

exec php-fpm
