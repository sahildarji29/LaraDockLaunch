#!/bin/bash

# Docker Compose Configuration Setup Script
# Creates production-ready docker-compose.yml for Laravel projects

set -e

# Input parameters
PROJECT_NAME=$1
PROJECT_PATH=$2
MASTER_IMAGE=$3
PHP_CONTAINER=$4
SHARED_NETWORK=$5
PROJECT_VOLUME=$6
CONTAINER_MOUNT_DIR=$7

# Validate input
if [ $# -ne 7 ]; then
    echo "Usage: $0 <project_name> <project_path> <master_image> <php_container> <shared_network> <project_volume> <container_mount_dir>"
    exit 1
fi

echo "🐳 Creating Docker Compose configuration for $PROJECT_NAME..."

# Create docker-compose.yml for individual PHP-FPM container with production-ready settings
tee "$PROJECT_PATH/docker-compose.yml" > /dev/null <<EOF
version: '3.8'

services:
  app:
    image: ${MASTER_IMAGE}
    container_name: ${PHP_CONTAINER}
    restart: unless-stopped
    
    # Resource limits for high-scale deployment
    deploy:
      resources:
        limits:
          memory: 256M
          cpus: '0.5'
        reservations:
          memory: 128M
          cpus: '0.25'
    
    # Security settings
    security_opt:
      - no-new-privileges:true
    read_only: false
    tmpfs:
      - /tmp:noexec,nosuid,size=100m
      - /var/tmp:noexec,nosuid,size=50m
    
    # Volume mounts for data persistence - using bind mounts for local access
    volumes:
      - ${PROJECT_PATH}:/var/www
      - ${PROJECT_NAME}_logs:/var/log/php
    
    # Network configuration
    networks:
      - ${SHARED_NETWORK}
    
    # Environment variables
    environment:
      - PROJECT_NAME=$PROJECT_NAME
      - CONTAINER_MOUNT_DIR=/var/www
      - HOST_UID=\${HOST_UID:-$(id -u)}
      - HOST_GID=\${HOST_GID:-$(id -g)}
      - SKIP_NPM=true
      - PHP_MEMORY_LIMIT=256M
      - PHP_MAX_EXECUTION_TIME=300
      - FPM_MAX_CHILDREN=10
      - FPM_MAX_REQUESTS=500
      - APP_ENV=production
      - APP_DEBUG=false
      - LOG_LEVEL=warning
    
    # Health check configuration
    healthcheck:
      test: ["CMD", "/usr/local/bin/healthcheck.sh"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s
    
    # Logging configuration
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
    
    # User and group settings - dynamically set by container
    
    # Process limits
    ulimits:
      nproc: 65535
      nofile:
        soft: 65535
        hard: 65535
    
    # Network optimizations for high-scale deployment
    sysctls:
      - net.core.somaxconn=1024
      - net.ipv4.tcp_keepalive_time=600
      - net.ipv4.tcp_keepalive_intvl=60
      - net.ipv4.tcp_keepalive_probes=3

# Named volumes for logs only (data is now bind mounted)
volumes:
  ${PROJECT_NAME}_logs:
    driver: local

# External shared network
networks:
  ${SHARED_NETWORK}:
    external: true
EOF

echo "✅ Docker Compose configuration created: $PROJECT_PATH/docker-compose.yml" 