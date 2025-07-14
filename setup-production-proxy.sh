#!/bin/bash

# Production Nginx Proxy Setup Script
# One-time setup to enable access to all Laravel projects without port numbers
# Run once with sudo on production server

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo -e "${CYAN}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║       🚀 Production Nginx Proxy Setup               ║${NC}"
echo -e "${CYAN}║   One-time setup for all Laravel projects           ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════════╝${NC}"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}❌ This script must be run with sudo${NC}"
    echo -e "${YELLOW}💡 Usage: sudo $0${NC}"
    exit 1
fi

# Validate environment
echo -e "${BLUE}🔍 Validating production environment...${NC}"

# Check if nginx is installed
if ! command -v nginx >/dev/null 2>&1; then
    echo -e "${YELLOW}📦 Installing nginx...${NC}"
    apt update && apt install -y nginx
    echo -e "${GREEN}✅ Nginx installed${NC}"
else
    echo -e "${GREEN}✅ Nginx already installed${NC}"
fi

# Check if Docker is available
if ! command -v docker >/dev/null 2>&1; then
    echo -e "${RED}❌ Docker is not installed${NC}"
    echo -e "${YELLOW}💡 Install Docker first: https://docs.docker.com/engine/install/ubuntu/${NC}"
    exit 1
fi

# Check if shared nginx container is running
if ! docker ps --format '{{.Names}}' | grep -q "^laravel_nginx_shared$"; then
    echo -e "${RED}❌ Shared nginx container 'laravel_nginx_shared' is not running${NC}"
    echo -e "${YELLOW}💡 Start it first by creating a project: make init PROJECT_NAME=test${NC}"
    exit 1
fi

# Get current container nginx port
NGINX_PORT=81
if [ -f /tmp/laravel_nginx_port ]; then
    source /tmp/laravel_nginx_port
    echo -e "${GREEN}✅ Container nginx running on port $NGINX_PORT${NC}"
else
    # Try to detect port from docker
    DETECTED_PORT=$(docker port laravel_nginx_shared 80/tcp 2>/dev/null | cut -d: -f2 || echo "")
    if [ -n "$DETECTED_PORT" ]; then
        NGINX_PORT=$DETECTED_PORT
        echo -e "${YELLOW}⚠️  Port detected from container: $NGINX_PORT${NC}"
        # Save for future use
        echo "NGINX_PORT=$NGINX_PORT" > /tmp/laravel_nginx_port
    else
        echo -e "${RED}❌ Cannot determine container nginx port${NC}"
        exit 1
    fi
fi

echo -e "${BLUE}📊 Production Configuration:${NC}"
echo "• Server: $(hostname)"
echo "• System nginx: Port 80 (public)"
echo "• Container nginx: Port $NGINX_PORT (internal)"
echo "• Architecture: Internet → System Nginx → Container Nginx → PHP-FPM"
echo ""

# Backup existing nginx configuration
echo -e "${BLUE}💾 Backing up existing nginx configuration...${NC}"
BACKUP_FILE="/etc/nginx/sites-available/default.backup.production.$(date +%Y%m%d_%H%M%S)"
if [ -f /etc/nginx/sites-available/default ]; then
    cp /etc/nginx/sites-available/default "$BACKUP_FILE"
    echo -e "${GREEN}✅ Backup created: $BACKUP_FILE${NC}"
else
    echo -e "${YELLOW}⚠️  No existing configuration to backup${NC}"
fi

# Create production nginx proxy configuration
echo -e "${BLUE}📝 Creating production nginx proxy configuration...${NC}"
tee /etc/nginx/sites-available/default > /dev/null <<EOF
# Laravel Container Infrastructure - Production Proxy
# Automatically routes all requests to shared nginx container
# Setup: $(date)
# Container Port: $NGINX_PORT

server {
    listen 80 default_server;
    listen [::]:80 default_server;
    
    # Accept all server names
    server_name _;
    
    # Security headers for production
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    add_header Permissions-Policy "geolocation=(), microphone=(), camera=()" always;
    
    # Proxy all requests to shared nginx container
    location / {
        proxy_pass http://127.0.0.1:$NGINX_PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-Host \$host;
        proxy_set_header X-Forwarded-Server \$host;
        
        # Production proxy settings
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
        proxy_redirect off;
        
        # Buffer settings for performance
        proxy_buffering on;
        proxy_buffer_size 8k;
        proxy_buffers 16 8k;
        proxy_busy_buffers_size 16k;
        
        # Handle large requests
        client_max_body_size 100M;
        
        # WebSocket support
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }
    
    # Health check endpoint
    location /health {
        access_log off;
        return 200 "production-nginx-proxy-healthy\n";
        add_header Content-Type text/plain;
    }
    
    # Nginx status (for monitoring)
    location /nginx_status {
        access_log off;
        stub_status on;
        allow 127.0.0.1;
        deny all;
    }
}
EOF

echo -e "${GREEN}✅ Production proxy configuration created${NC}"

# Test nginx configuration
echo -e "${BLUE}🧪 Testing nginx configuration...${NC}"
if nginx -t; then
    echo -e "${GREEN}✅ Nginx configuration is valid${NC}"
else
    echo -e "${RED}❌ Invalid nginx configuration${NC}"
    if [ -f "$BACKUP_FILE" ]; then
        echo -e "${YELLOW}🔄 Restoring backup...${NC}"
        cp "$BACKUP_FILE" /etc/nginx/sites-available/default
    fi
    exit 1
fi

# Start and enable nginx
echo -e "${BLUE}🚀 Starting nginx service...${NC}"
systemctl enable nginx
systemctl start nginx
systemctl reload nginx
echo -e "${GREEN}✅ Nginx service started and enabled${NC}"

# Test the proxy functionality
echo -e "${BLUE}🧪 Testing proxy functionality...${NC}"
sleep 3

# Test health endpoint
if curl -s -f http://localhost/health >/dev/null 2>&1; then
    echo -e "${GREEN}✅ Proxy health check working${NC}"
else
    echo -e "${YELLOW}⚠️  Health check failed, but proxy may still work${NC}"
fi

# Test actual Laravel project if available
echo -e "${BLUE}🔍 Testing Laravel project access...${NC}"
PROJECTS_DIR="/var/www/copilot-infra"
if [ -d "$PROJECTS_DIR" ]; then
    TEST_PROJECT=$(ls "$PROJECTS_DIR" | head -1 2>/dev/null || echo "")
    if [ -n "$TEST_PROJECT" ]; then
        # Try different domain formats
        for domain in "${TEST_PROJECT}.loc" "${TEST_PROJECT}.com" "${TEST_PROJECT}.example.com"; do
            if curl -s -H "Host: $domain" http://localhost | grep -q "Laravel" 2>/dev/null; then
                echo -e "${GREEN}✅ Laravel project '$TEST_PROJECT' accessible via $domain${NC}"
                WORKING_DOMAIN="$domain"
                break
            fi
        done
        
        if [ -z "${WORKING_DOMAIN:-}" ]; then
            echo -e "${YELLOW}⚠️  Could not test Laravel project access${NC}"
        fi
    else
        echo -e "${YELLOW}⚠️  No Laravel projects found to test${NC}"
    fi
else
    echo -e "${YELLOW}⚠️  Projects directory not found${NC}"
fi

# Create monitoring script
echo -e "${BLUE}📊 Creating monitoring script...${NC}"
tee /usr/local/bin/laravel-proxy-monitor > /dev/null <<'EOF'
#!/bin/bash
# Laravel Proxy Monitor
# Checks if proxy is working correctly

NGINX_PORT=81
if [ -f /tmp/laravel_nginx_port ]; then
    source /tmp/laravel_nginx_port
fi

echo "Laravel Proxy Status:"
echo "===================="
echo "System Nginx: $(systemctl is-active nginx)"
echo "Container Nginx: $(docker ps --format '{{.Status}}' --filter 'name=laravel_nginx_shared' || echo 'Not running')"
echo "Proxy Health: $(curl -s -o /dev/null -w '%{http_code}' http://localhost/health 2>/dev/null || echo 'Failed')"
echo "Container Port: $NGINX_PORT"
echo ""
echo "Test Commands:"
echo "curl -H 'Host: project.domain' http://localhost"
echo "curl http://localhost/health"
EOF

chmod +x /usr/local/bin/laravel-proxy-monitor

# Summary
echo ""
echo -e "${GREEN}🎉 Production Nginx Proxy Setup Complete!${NC}"
echo -e "${CYAN}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║                    SUCCESS SUMMARY                   ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BLUE}✅ Configuration:${NC}"
echo "• System nginx configured as proxy on port 80"
echo "• Routes all requests to container nginx on port $NGINX_PORT"
echo "• Production security headers enabled"
echo "• WebSocket support included"
echo "• Monitoring endpoints available"
echo ""
echo -e "${BLUE}✅ Access Methods:${NC}"
echo "• Direct: http://server-ip/"
echo "• With domain: http://yourdomain.com/"
echo "• Health check: http://server-ip/health"
echo "• Nginx status: http://server-ip/nginx_status"
echo ""
echo -e "${BLUE}✅ Future Projects:${NC}"
echo "• All new Laravel projects will automatically work without port numbers"
echo "• No additional sudo commands needed"
echo "• Just point your domain DNS to this server"
echo ""
echo -e "${BLUE}🔧 Monitoring:${NC}"
echo "• Run: laravel-proxy-monitor"
echo "• Logs: journalctl -u nginx -f"
echo "• Config: /etc/nginx/sites-available/default"
echo "• Backup: $BACKUP_FILE"
echo ""
echo -e "${GREEN}🚀 Your production proxy is ready!${NC}"
echo -e "${PURPLE}All Laravel projects will now be accessible without port numbers.${NC}" 