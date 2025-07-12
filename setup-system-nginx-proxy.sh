#!/bin/bash

# System Nginx Reverse Proxy Setup Script
# Configures system nginx to proxy to shared nginx container
# Works without sudo by providing clear instructions

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🚀 Setting up System Nginx as Reverse Proxy${NC}"
echo "================================================"
echo ""

# Check if nginx is installed
if ! command -v nginx >/dev/null 2>&1; then
    echo -e "${RED}❌ nginx is not installed${NC}"
    echo "Please install nginx: sudo apt install nginx"
    exit 1
fi

# Get the current nginx port
NGINX_PORT=82
if [ -f /tmp/laravel_nginx_port ]; then
    source /tmp/laravel_nginx_port
fi

echo -e "${BLUE}📊 Current Configuration:${NC}"
echo "• System nginx: Running on port 80"
echo "• Shared nginx container: laravel_nginx_shared"
echo "• Shared nginx port: $NGINX_PORT"
echo ""

# Check if shared nginx container is running
if ! docker ps --format '{{.Names}}' | grep -q "^laravel_nginx_shared$"; then
    echo -e "${RED}❌ Shared nginx container is not running${NC}"
    echo "Please start the shared nginx container first"
    exit 1
fi

# Check if we can write to nginx configuration
if [ ! -w /etc/nginx/sites-available/default ]; then
    echo -e "${YELLOW}⚠️  Cannot write to nginx configuration (requires sudo)${NC}"
    echo ""
    echo -e "${BLUE}📋 Manual Setup Required:${NC}"
    echo "Please run the following command to set up the nginx proxy:"
    echo ""
    echo "sudo $0"
    echo ""
    echo -e "${BLUE}🔧 Or manually configure /etc/nginx/sites-available/default:${NC}"
    echo "Replace the content with:"
    echo ""
    echo "server {"
    echo "    listen 80 default_server;"
    echo "    listen [::]:80 default_server;"
    echo "    server_name _;"
    echo ""
    echo "    location / {"
    echo "        proxy_pass http://127.0.0.1:$NGINX_PORT;"
    echo "        proxy_set_header Host \$host;"
    echo "        proxy_set_header X-Real-IP \$remote_addr;"
    echo "        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;"
    echo "        proxy_set_header X-Forwarded-Proto \$scheme;"
    echo "    }"
    echo ""
    echo "    location /health {"
    echo "        access_log off;"
    echo "        return 200 \"system-nginx-proxy-healthy\\n\";"
    echo "        add_header Content-Type text/plain;"
    echo "    }"
    echo "}"
    echo ""
    echo "Then reload nginx:"
    echo "sudo systemctl reload nginx"
    echo ""
    exit 1
fi

# Backup existing nginx configuration
echo -e "${BLUE}💾 Backing up existing nginx configuration...${NC}"
if [ -f /etc/nginx/sites-available/default ]; then
    cp /etc/nginx/sites-available/default /etc/nginx/sites-available/default.backup.$(date +%Y%m%d_%H%M%S)
    echo -e "${GREEN}✅ Backup created${NC}"
else
    echo -e "${YELLOW}⚠️  No existing configuration to backup${NC}"
fi

# Create nginx proxy configuration
echo -e "${BLUE}📝 Creating nginx proxy configuration...${NC}"
tee /etc/nginx/sites-available/default > /dev/null <<EOF
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;

    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;

    # Proxy to shared nginx container
    location / {
        proxy_pass http://127.0.0.1:$NGINX_PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        # Proxy timeouts
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
        
        # Buffer settings
        proxy_buffering on;
        proxy_buffer_size 4k;
        proxy_buffers 8 4k;
    }

    # Health check endpoint
    location /health {
        access_log off;
        return 200 "system-nginx-proxy-healthy\n";
        add_header Content-Type text/plain;
    }
}
EOF

echo -e "${GREEN}✅ Nginx proxy configuration created${NC}"

# Test nginx configuration
echo -e "${BLUE}🧪 Testing nginx configuration...${NC}"
if nginx -t 2>/dev/null; then
    echo -e "${GREEN}✅ Nginx configuration is valid${NC}"
else
    echo -e "${YELLOW}⚠️  Cannot test nginx configuration (requires sudo)${NC}"
    echo "Please run: sudo nginx -t"
fi

# Reload nginx
echo -e "${BLUE}🔄 Reloading nginx...${NC}"
if systemctl reload nginx 2>/dev/null; then
    echo -e "${GREEN}✅ Nginx reloaded successfully${NC}"
else
    echo -e "${YELLOW}⚠️  Cannot reload nginx (requires sudo)${NC}"
    echo "Please run: sudo systemctl reload nginx"
fi

# Test the proxy
echo -e "${BLUE}🧪 Testing proxy...${NC}"
sleep 2

if curl -s -o /dev/null -w "%{http_code}" http://localhost/health 2>/dev/null | grep -q "200"; then
    echo -e "${GREEN}✅ System nginx proxy is working${NC}"
else
    echo -e "${YELLOW}⚠️  Proxy may need a moment to start${NC}"
    echo "Please reload nginx manually: sudo systemctl reload nginx"
fi

# Test virtual host access
echo -e "${BLUE}🧪 Testing virtual host access...${NC}"
if curl -s -H "Host: port-fix-test.loc" http://localhost 2>/dev/null | head -5 | grep -q "Laravel"; then
    echo -e "${GREEN}✅ Virtual host routing is working${NC}"
else
    echo -e "${YELLOW}⚠️  Virtual host routing may need testing${NC}"
fi

echo ""
echo -e "${GREEN}🎉 System Nginx Proxy Setup Complete!${NC}"
echo ""
echo -e "${BLUE}📋 Access Information:${NC}"
echo "• Direct access: http://localhost"
echo "• Virtual host access: http://project.loc (with hosts entry)"
echo "• Health check: http://localhost/health"
echo ""
echo -e "${BLUE}🔧 Hosts Entry (Optional):${NC}"
echo "Add this line to /etc/hosts for cleaner URLs:"
echo "127.0.0.1 project.loc"
echo ""
echo -e "${BLUE}📊 Nginx Status:${NC}"
if systemctl status nginx --no-pager -l 2>/dev/null; then
    echo "✅ Nginx is running"
else
    echo "⚠️  Cannot check nginx status (requires sudo)"
    echo "Please run: sudo systemctl status nginx"
fi
echo ""
echo -e "${BLUE}💡 To restore original nginx config:${NC}"
echo "sudo cp /etc/nginx/sites-available/default.backup.* /etc/nginx/sites-available/default"
echo "sudo systemctl reload nginx" 