#!/bin/bash

# Environment Setup Script for High-Scale Laravel Infrastructure
# Configures the system for non-sudo Docker usage

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🚀 High-Scale Laravel Infrastructure - Environment Setup${NC}"
echo "======================================================="
echo ""

# Check if Docker is installed
if ! command -v docker >/dev/null 2>&1; then
    echo -e "${RED}❌ Docker is not installed${NC}"
    echo "Please install Docker first:"
    echo "  curl -fsSL https://get.docker.com -o get-docker.sh"
    echo "  sudo sh get-docker.sh"
    exit 1
fi

# Check if Docker Compose is installed
if ! command -v docker-compose >/dev/null 2>&1; then
    echo -e "${RED}❌ Docker Compose is not installed${NC}"
    echo "Please install Docker Compose first:"
    echo "  sudo curl -L \"https://github.com/docker/compose/releases/latest/download/docker-compose-\$(uname -s)-\$(uname -m)\" -o /usr/local/bin/docker-compose"
    echo "  sudo chmod +x /usr/local/bin/docker-compose"
    exit 1
fi

echo -e "${GREEN}✅ Docker and Docker Compose are installed${NC}"

# Check if user is already in docker group
if groups | grep -q docker; then
    echo -e "${GREEN}✅ User is already in the docker group${NC}"
else
    echo -e "${YELLOW}⚠️  User is not in the docker group${NC}"
    echo "Adding user to docker group..."
    
    if sudo usermod -aG docker $USER; then
        echo -e "${GREEN}✅ User added to docker group successfully${NC}"
        echo -e "${YELLOW}⚠️  Please log out and log back in, or run: newgrp docker${NC}"
        
        # Try to activate the group immediately
        echo "Attempting to activate docker group..."
        if newgrp docker; then
            echo -e "${GREEN}✅ Docker group activated${NC}"
        else
            echo -e "${YELLOW}⚠️  Please log out and log back in for changes to take effect${NC}"
        fi
    else
        echo -e "${RED}❌ Failed to add user to docker group${NC}"
        exit 1
    fi
fi

# Test Docker without sudo
echo ""
echo "Testing Docker access without sudo..."
if docker ps >/dev/null 2>&1; then
    echo -e "${GREEN}✅ Docker works without sudo${NC}"
else
    echo -e "${RED}❌ Docker still requires sudo${NC}"
    echo "Please log out and log back in, or run: newgrp docker"
    exit 1
fi

# Check Docker daemon status
if docker info >/dev/null 2>&1; then
    echo -e "${GREEN}✅ Docker daemon is running${NC}"
else
    echo -e "${RED}❌ Docker daemon is not running${NC}"
    echo "Please start Docker daemon:"
    echo "  sudo systemctl start docker"
    echo "  sudo systemctl enable docker"
    exit 1
fi

# Create necessary directories
echo ""
echo "Creating necessary directories..."

BASE_DIR="/var/www/copilot-infra"
NGINX_CONFIG_DIR="/var/www/nginx-configs"

# Create base directory for projects
if [ ! -d "$BASE_DIR" ]; then
    echo "Creating base directory: $BASE_DIR"
    if sudo mkdir -p "$BASE_DIR"; then
        echo -e "${GREEN}✅ Base directory created${NC}"
    else
        echo -e "${RED}❌ Failed to create base directory${NC}"
        exit 1
    fi
else
    echo -e "${GREEN}✅ Base directory already exists${NC}"
fi

# Create nginx configs directory
if [ ! -d "$NGINX_CONFIG_DIR" ]; then
    echo "Creating nginx configs directory: $NGINX_CONFIG_DIR"
    if sudo mkdir -p "$NGINX_CONFIG_DIR"; then
        echo -e "${GREEN}✅ Nginx configs directory created${NC}"
    else
        echo -e "${RED}❌ Failed to create nginx configs directory${NC}"
        exit 1
    fi
else
    echo -e "${GREEN}✅ Nginx configs directory already exists${NC}"
fi

# Set proper permissions
echo ""
echo "Setting proper permissions..."
if sudo chown -R $USER:$USER "$BASE_DIR" "$NGINX_CONFIG_DIR"; then
    echo -e "${GREEN}✅ Permissions set successfully${NC}"
else
    echo -e "${YELLOW}⚠️  Failed to set permissions, but continuing...${NC}"
fi

# Test system resources
echo ""
echo "Checking system resources..."
echo "CPU cores: $(nproc)"
echo "Memory: $(free -h | grep '^Mem:' | awk '{print $2}')"
echo "Disk space: $(df -h / | tail -1 | awk '{print $4}') available"

# Recommendations
echo ""
echo -e "${BLUE}📋 System Recommendations:${NC}"
echo "• For high-scale deployment (300-400 containers):"
echo "  - Recommended: 64+ CPU cores, 128GB+ RAM"
echo "  - Current: $(nproc) CPU cores, $(free -h | grep '^Mem:' | awk '{print $2}') RAM"
echo ""
echo "• For development (10-20 containers):"
echo "  - Minimum: 4+ CPU cores, 8GB+ RAM"
echo ""

# Final status
echo -e "${GREEN}🎉 Environment setup completed successfully!${NC}"
echo ""
echo "Next steps:"
echo "1. Build the master image:"
echo "   make build-master"
echo ""
echo "2. Create your first project:"
echo "   make init PROJECT_NAME=myapp"
echo ""
echo "3. Add hosts entry (optional):"
echo "   make add-host PROJECT_NAME=myapp"
echo ""
echo "4. Access your project:"
echo "   http://myapp.loc"
echo ""
echo -e "${BLUE}📚 For more information, see README.md${NC}" 