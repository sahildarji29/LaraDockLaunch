# Reverse Proxy Solution for Laravel Container Infrastructure

## Overview

This solution enables accessing Laravel applications at `http://project.loc` without specifying any port, even though the shared nginx container runs on a dynamic port (e.g., port 82).

## Architecture

```
Internet Request → System Nginx (Port 80) → Shared Nginx Container (Port 82) → PHP-FPM Containers
```

### Components

1. **System Nginx** (Port 80): Acts as a reverse proxy
2. **Shared Nginx Container** (Port 82): Handles virtual host routing
3. **PHP-FPM Containers**: Individual Laravel applications

## Solution Implementation

### 1. System Nginx Reverse Proxy

The system nginx is configured to proxy all requests to the shared nginx container:

```nginx
server {
    listen 80 default_server;
    server_name _;

    location / {
        proxy_pass http://127.0.0.1:82;  # Dynamic port
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

### 2. Dynamic Port Detection

The system automatically detects the shared nginx port from `/tmp/laravel_nginx_port` and updates the proxy configuration accordingly.

### 3. Automatic Setup

The initialization script (`init-laravel-container.sh`) now automatically:
- Sets up the system nginx proxy on first project creation
- Detects if proxy is already configured on subsequent projects
- Updates the proxy configuration when the shared nginx port changes

## Scripts Created

### 1. `setup-system-nginx-proxy.sh`
- Configures system nginx as reverse proxy
- Backs up existing nginx configuration
- Tests and validates the setup
- Requires sudo privileges

### 2. `update-nginx-proxy-port.sh`
- Updates system nginx proxy when shared nginx port changes
- Can be run manually or automatically
- Requires sudo privileges

### 3. `setup-reverse-proxy.sh` (Alternative)
- Creates a Docker-based reverse proxy on port 8080
- Used when system nginx is not available
- Includes port forwarding setup

### 4. `setup-port-forwarding.sh` (Alternative)
- Sets up iptables port forwarding from 80 to 8080
- Alternative approach when system nginx is busy

## Usage

### Accessing Applications

1. **With hosts entry** (Recommended):
   ```bash
   # Add to /etc/hosts
   127.0.0.1 project.loc
   
   # Access without port
   http://project.loc
   ```

2. **Direct access**:
   ```bash
   # Access without port
   http://localhost
   ```

3. **Health check**:
   ```bash
   curl http://localhost/health
   ```

### Creating New Projects

```bash
# Create new project (automatically sets up proxy)
./init-laravel-container.sh my-project /var/www

# Add to hosts
echo "127.0.0.1 my-project.loc" | sudo tee -a /etc/hosts

# Access without port
http://my-project.loc
```

## Benefits

1. **No Port Specification**: Access applications without `:82` in URLs
2. **Automatic Setup**: Proxy is configured automatically on first project
3. **Dynamic Port Handling**: Automatically adapts to changing shared nginx ports
4. **System Integration**: Uses existing system nginx for better performance
5. **Backup & Recovery**: Original nginx configuration is backed up

## Configuration Files

### System Nginx Configuration
- **Location**: `/etc/nginx/sites-available/default`
- **Backup**: `/etc/nginx/sites-available/default.backup.*`
- **Auto-update**: When shared nginx port changes

### Shared Nginx Container
- **Port**: Dynamic (currently 82)
- **Internal Port**: Always 80
- **Configuration**: `/var/www/nginx-configs/`

## Troubleshooting

### Check Proxy Status
```bash
# Test proxy
curl -s -o /dev/null -w "%{http_code}" http://localhost

# Check nginx status
sudo systemctl status nginx

# View nginx configuration
sudo nginx -t
```

### Restore Original Configuration
```bash
# Find backup
ls /etc/nginx/sites-available/default.backup.*

# Restore
sudo cp /etc/nginx/sites-available/default.backup.* /etc/nginx/sites-available/default
sudo systemctl reload nginx
```

### Manual Port Update
```bash
# Update proxy for new port
sudo ./update-nginx-proxy-port.sh
```

## Security Considerations

1. **System Nginx**: Runs with system privileges, properly secured
2. **Headers**: Security headers are preserved through proxy
3. **Access Control**: Can be extended with additional nginx rules
4. **SSL**: Can be configured for HTTPS termination

## Performance

1. **Minimal Overhead**: System nginx is highly optimized
2. **Connection Pooling**: Efficient proxy connections
3. **Caching**: Can be extended with nginx caching
4. **Load Balancing**: Architecture supports future load balancing

## Future Enhancements

1. **SSL/TLS Support**: Automatic SSL certificate management
2. **Load Balancing**: Multiple shared nginx containers
3. **Caching**: Redis/Memcached integration
4. **Monitoring**: Health checks and metrics
5. **Auto-scaling**: Dynamic container scaling

## Summary

This solution provides seamless access to Laravel applications without port specification while maintaining the high-scale architecture benefits. The system nginx acts as an intelligent reverse proxy that automatically adapts to the dynamic shared nginx port, providing a clean and professional user experience. 