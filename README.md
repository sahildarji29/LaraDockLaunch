# Laravel Container Initialization with Virtual Hosts

A robust shell script and Makefile system for quickly setting up Laravel projects with Docker containers using virtual host configuration. This tool automatically creates a complete Laravel development environment with PHP-FPM, Nginx, and a reverse proxy for seamless virtual host routing.

## ✨ Features

- **Dual Environment Support**: Deploy locally (`PROJECT.loc`) or production (`PROJECT.laracopilot.com`)
- **Virtual Host Support**: Access projects via custom domains with automatic subdomain creation
- **One-command Laravel setup**: Initialize a complete Laravel project with Docker containers
- **Direct File Access**: Laravel files are accessible in the host directory for easy editing
- **Automatic Laravel installation**: Downloads and configures Laravel directly in the project directory
- **Smart Port Detection**: Automatically finds available ports in 80-90 range to avoid conflicts
- **Proper Ownership**: All projects created with www-data ownership for web server compatibility
- **Production Ready**: Enhanced nginx config with security headers and performance optimizations
- **Reverse Proxy**: Shared Nginx proxy for handling multiple virtual hosts
- **Bind Mount Architecture**: Project files are directly accessible on the host for development
- **Health checks**: Proper container health monitoring and startup verification
- **Hosts file management**: Built-in tools for managing `/etc/hosts` entries
- **Error handling**: Comprehensive error checking and graceful failure handling
- **Project management**: Easy cleanup and status checking for projects
- **Dependency validation**: Checks for Docker and Docker Compose before starting
- **IDE Integration**: Edit Laravel files directly with your favorite IDE/editor

## 🔧 Prerequisites

- Docker (with daemon running)
- Docker Compose
- Make (for using the Makefile)
- Bash shell
- Sudo access (for managing `/etc/hosts` file and setting www-data ownership)

## 🚀 Quick Start

### Initialize a new Laravel project

**Local Development:**
```bash
make init PROJECT_NAME=my-app
# Creates: my-app.loc
```

**Production Deployment:**
```bash
make init PROJECT_NAME=api ENVIRONMENT=production
# Creates: api.laracopilot.com subdomain
```

### Add virtual host to your system (Local only)
```bash
make add-host PROJECT_NAME=my-app
# or manually: ./manage-hosts.sh add my-app
```

### Access your application
- **Local:** `http://my-app.loc:PORT` (PORT auto-detected)
- **Production:** `http://api.laracopilot.com` (requires DNS configuration)

### Check project status
```bash
make status PROJECT_NAME=my-app
```

### Clean up a project
```bash
make clean PROJECT_NAME=my-app
make remove-host PROJECT_NAME=my-app
```

### Get help
```bash
make help
```

## 📋 Usage Examples

### Local Development Setup
```bash
# Create the project
make init PROJECT_NAME=blog

# Add to hosts file
make add-host PROJECT_NAME=blog

# Visit http://blog.loc:PORT
```

### Production Deployment for LaraCopilot.com
```bash
# Create production project
make init PROJECT_NAME=api ENVIRONMENT=production

# Configure DNS: api.laracopilot.com -> Server IP
# Visit http://api.laracopilot.com
```

### Multiple Projects (Mixed Environments)
```bash
# Local development projects
make init PROJECT_NAME=dev-api ENVIRONMENT=local
make init PROJECT_NAME=testing

# Production subdomains
make init PROJECT_NAME=docs ENVIRONMENT=production
make init PROJECT_NAME=admin ENVIRONMENT=production

# Add local projects to hosts file
make add-host PROJECT_NAME=dev-api
make add-host PROJECT_NAME=testing

# Access URLs:
# Local: http://dev-api.loc:PORT, http://testing.loc:PORT
# Production: http://docs.laracopilot.com, http://admin.laracopilot.com
```

### Manage hosts entries
```bash
# List all virtual hosts
make list-hosts

# Remove a specific host entry
make remove-host PROJECT_NAME=blog

# Get hosts management help
make hosts-help
```

## 🏗️ What Gets Created

When you run the initialization, the following structure is created:

```
/var/www/copilot-infra/PROJECT_NAME/
├── app/                    # Laravel application code (editable)
├── bootstrap/              # Laravel bootstrap files
├── config/                 # Laravel configuration files (editable)
├── database/               # Migrations, seeders, factories (editable)
├── public/                 # Web-accessible files (editable)
├── resources/              # Views, CSS, JS, language files (editable)
├── routes/                 # Route definitions (editable)
├── storage/                # Laravel storage directory
├── tests/                  # Test files (editable)
├── vendor/                 # Composer dependencies
├── .env                    # Environment configuration (editable)
├── artisan                 # Laravel command-line tool
├── composer.json           # Composer dependencies (editable)
├── Dockerfile              # PHP-FPM container configuration
├── docker-compose.yml      # Container orchestration
└── nginx.conf             # Nginx virtual host configuration

Docker Resources:
├── PROJECT_NAME_php        # PHP-FPM container
├── PROJECT_NAME_nginx      # Nginx container for the project
├── laravel_proxy           # Shared reverse proxy (created once)
├── PROJECT_NAME_net        # Project network
└── laravel_proxy_net       # Shared proxy network
```

## 📝 Development Workflow

### File Editing
All Laravel files are directly accessible in `/var/www/copilot-infra/PROJECT_NAME/` for editing:

**Note**: Files are owned by www-data. For easier editing, add your user to the www-data group:
```bash
sudo usermod -a -G www-data $USER
# Log out and back in for changes to take effect
```

## 🌍 Production Deployment Guide

### DNS Configuration for LaraCopilot.com Subdomains

1. **Create Production Project:**
   ```bash
   make init PROJECT_NAME=api ENVIRONMENT=production
   ```

2. **Configure DNS A Record:**
   - Add A record: `api.laracopilot.com` → `YOUR_SERVER_IP`
   - DNS propagation may take 5-60 minutes

3. **Verify DNS Resolution:**
   ```bash
   nslookup api.laracopilot.com
   dig api.laracopilot.com
   ```

4. **Access Your Application:**
   - HTTP: `http://api.laracopilot.com`
   - For HTTPS, configure SSL certificate

### SSL Certificate Setup (Recommended for Production)

```bash
# Using Let's Encrypt (example)
sudo apt install certbot python3-certbot-nginx
sudo certbot --nginx -d api.laracopilot.com

# Manual certificate (if you have custom certs)
# Update nginx config to include SSL configuration
```

### Production Security Checklist

- ✅ DNS A record configured
- ✅ Firewall allows ports 80/443
- ✅ SSL certificate installed
- ✅ Environment variables secured
- ✅ Laravel app key generated
- ✅ Database credentials configured
- ✅ File permissions set correctly (www-data)

```bash
# Edit routes
nano /var/www/copilot-infra/my-app/routes/web.php

# Edit views
code /var/www/copilot-infra/my-app/resources/views/

# Edit controllers
vim /var/www/copilot-infra/my-app/app/Http/Controllers/

# Edit configuration
gedit /var/www/copilot-infra/my-app/config/app.php
```

### Laravel Commands
Run artisan commands through the container:

```bash
# Generate controller
docker exec my-app_php php /var/www/artisan make:controller HomeController

# Run migrations
docker exec my-app_php php /var/www/artisan migrate

# Generate model
docker exec my-app_php php /var/www/artisan make:model Post

# Clear cache
docker exec my-app_php php /var/www/artisan cache:clear

# Install packages
docker exec my-app_php composer require laravel/sanctum
```

### Real-time Development
- **Instant Changes**: File modifications are immediately reflected in the running application
- **No Rebuilds**: No need to rebuild containers when editing code
- **IDE Support**: Full IDE/editor support with syntax highlighting, debugging, etc.
- **Version Control**: Git works normally in the project directory

### Quick Test Example
```bash
# Create a new project
make init PROJECT_NAME=demo
make add-host PROJECT_NAME=demo

# Edit the welcome route
echo "<?php
use Illuminate\Support\Facades\Route;
Route::get('/', function () {
    return '<h1>Hello from Demo Project!</h1>';
});" > /var/www/copilot-infra/demo/routes/web.php

# Visit http://demo.loc to see your changes instantly!
```

## 🌐 Virtual Host Architecture

### Reverse Proxy Setup
- **Shared Proxy**: One `laravel_proxy` container handles all virtual hosts
- **Automatic Discovery**: Uses `nginxproxy/nginx-proxy` for automatic configuration
- **Smart Port Selection**: Automatically finds available ports in 80-90 range
- **Domain Routing**: Routes requests based on `Host` header

### Virtual Host Configuration
- **Local Pattern**: `PROJECT_NAME.loc` (e.g., `myapp.loc`, `blog.loc`)
- **Production Pattern**: `PROJECT_NAME.laracopilot.com` (e.g., `api.laracopilot.com`, `docs.laracopilot.com`)
- **Local Resolution**: Uses `/etc/hosts` file for local domain resolution
- **Production Resolution**: Requires DNS A record configuration
- **SSL Ready**: Enhanced for production with security headers and HTTPS support

### LaraCopilot.com Integration
This infrastructure is designed to work with the [LaraCopilot AI-powered Laravel development platform](https://laracopilot.com/). 

**Production Deployment Features:**
- **Automatic Subdomains**: Creates `PROJECT_NAME.laracopilot.com` subdomains
- **DNS Configuration**: Requires A record pointing to your server IP
- **Security Headers**: Production-ready nginx configuration with security headers
- **Performance Optimization**: Static file caching and optimized FastCGI settings
- **SSL Ready**: Prepared for HTTPS certificate configuration

### File Ownership & Permissions
- **Base Directory**: `/var/www/copilot-infra/` owned by www-data:www-data (755)
- **Project Files**: All Laravel files owned by www-data:www-data (755)
- **Writable Directories**: `storage/` and `bootstrap/cache/` (775)
- **Configuration Files**: `.env`, `docker-compose.yml`, etc. (644)
- **Security**: Proper web server ownership prevents permission issues

## 🔍 Technical Details

### Container Architecture
- **PHP Container**: PHP 8.3-FPM with Composer, Laravel dependencies
- **Nginx Container**: Project-specific Nginx with virtual host configuration
- **Reverse Proxy**: Shared nginx-proxy container for routing
- **Bind Mount Storage**: Project files directly accessible on host filesystem
- **Network Isolation**: Projects connected via shared proxy network

### Laravel Installation Process
1. Creates base directory `/var/www/copilot-infra/` with www-data ownership
2. Creates project directory in `/var/www/copilot-infra/PROJECT_NAME/`
3. Installs Laravel directly in the host directory using Composer
4. Sets proper www-data ownership for all Laravel files and directories
5. Configures appropriate permissions for web server access
6. Creates Docker containers with bind mounts to the project directory
7. Sets up proxy network if not exists
8. Configures environment and generates application key
9. Connects to reverse proxy for virtual host routing
10. Verifies installation with health checks

### Hosts File Management
The included `manage-hosts.sh` script provides:
- **Add entries**: `./manage-hosts.sh add PROJECT_NAME`
- **Remove entries**: `./manage-hosts.sh remove PROJECT_NAME`
- **List entries**: `./manage-hosts.sh list`
- **Automatic validation**: Checks for existing entries

## 🛠️ Advanced Usage

### Direct script usage
```bash
# Local development
./init-laravel-container.sh project_name /var/www/copilot-infra

# Production deployment
ENVIRONMENT=production ./init-laravel-container.sh project_name /var/www/copilot-infra
```

### Container access
```bash
docker exec -it PROJECT_NAME_php bash
```

### View container logs
```bash
docker logs PROJECT_NAME_php
docker logs PROJECT_NAME_nginx
docker logs laravel_proxy
```

### Manual Laravel commands
```bash
# Access the PHP container
docker exec -it PROJECT_NAME_php bash

# Run artisan commands
docker exec PROJECT_NAME_php php /var/www/artisan migrate
docker exec PROJECT_NAME_php php /var/www/artisan make:controller HomeController
docker exec PROJECT_NAME_php php /var/www/artisan tinker

# Install Composer packages
docker exec PROJECT_NAME_php composer require package/name

# Run tests
docker exec PROJECT_NAME_php php /var/www/artisan test
```

### File Editing and Development
```bash
# Open project in your favorite IDE
code /var/www/copilot-infra/PROJECT_NAME/
subl /var/www/copilot-infra/PROJECT_NAME/
vim /var/www/copilot-infra/PROJECT_NAME/

# Edit specific files
nano /var/www/copilot-infra/PROJECT_NAME/routes/web.php
gedit /var/www/copilot-infra/PROJECT_NAME/.env
```

### Proxy management
```bash
# Clean up the shared proxy (affects all projects)
make clean-proxy

# Restart the proxy
docker restart laravel_proxy
```

## 🔧 Troubleshooting

### Common Issues

**Virtual host not accessible**
- Check `/etc/hosts` entry: `grep 'PROJECT_NAME.loc' /etc/hosts`
- Verify proxy is running: `docker ps | grep laravel_proxy`
- Check project containers: `make status PROJECT_NAME=myapp`

**Laravel installation fails**
- Check Docker daemon is running: `docker info`
- Verify internet connection for Composer downloads
- Check container logs: `docker logs PROJECT_NAME_php`

**Port conflicts**
- The system automatically detects available ports in 80-90 range
- If all ports are busy, it falls back to port 8080
- Stop conflicting services: `sudo systemctl stop apache2 nginx`
- Check what's using ports: `sudo netstat -tulpn | grep :8[0-9]`
- Kill the proxy and restart: `make clean-proxy && make init PROJECT_NAME=test`

**Permission issues with hosts file**
- Ensure you have sudo access
- Check hosts file permissions: `ls -la /etc/hosts`
- Use the manual commands if script fails

**Directory ownership issues**
- Base directory not accessible: `sudo chown www-data:www-data /var/www/copilot-infra`
- Project creation fails: Check if you have sudo access
- Files not editable: Add your user to www-data group: `sudo usermod -a -G www-data $USER`

**Production deployment issues**
- Subdomain not accessible: Verify DNS A record points to server IP
- Check DNS propagation: `nslookup PROJECT_NAME.laracopilot.com`
- Firewall blocking: Ensure ports 80/443 are open
- SSL certificate needed: Configure Let's Encrypt or custom certificate
- Domain ownership: Ensure you control the laracopilot.com domain and DNS

**Laravel files not accessible for editing**
- Verify project directory exists: `ls -la /var/www/copilot-infra/PROJECT_NAME/`
- Check file permissions: `ls -la /var/www/copilot-infra/PROJECT_NAME/app/`
- Ensure containers are using bind mounts: `docker inspect PROJECT_NAME_php`

**File permission issues**
- Check ownership: `ls -la /var/www/copilot-infra/PROJECT_NAME/`
- Fix www-data ownership: `sudo chown -R www-data:www-data /var/www/copilot-infra/PROJECT_NAME/`
- Set proper permissions: `sudo chmod -R 755 /var/www/copilot-infra/PROJECT_NAME/`
- Ensure storage directories are writable: `sudo chmod -R 775 /var/www/copilot-infra/PROJECT_NAME/storage/ /var/www/copilot-infra/PROJECT_NAME/bootstrap/cache/`

### Status Command Output

The `make status` command provides comprehensive information:
- **Docker Containers**: Running status and virtual host configuration
- **Docker Volumes**: Volume names and drivers
- **Networks**: Network configuration including proxy network
- **Laravel Status**: Application health and version

### Cleanup Issues

If cleanup fails:
```bash
# Force remove project containers
docker rm -f PROJECT_NAME_php PROJECT_NAME_nginx

# Remove networks
docker network rm PROJECT_NAME_net

# Remove project directory
rm -rf /var/www/copilot-infra/PROJECT_NAME

# Clean up hosts entry
./manage-hosts.sh remove PROJECT_NAME
```

## 🎯 Best Practices

1. **Use descriptive project names**: Helps identify projects and virtual hosts
2. **Consistent naming**: Use lowercase, hyphens for multi-word projects
3. **Regular cleanup**: Remove unused projects and hosts entries
4. **Monitor proxy**: Keep an eye on the shared proxy container
5. **File Permissions**: Keep proper permissions on Laravel storage and cache directories
6. **Version Control**: Initialize git in your project directory for version control
7. **Environment Files**: Keep `.env` files secure and don't commit them to version control
8. **Hosts file management**: Use the provided scripts for consistency
9. **IDE Configuration**: Configure your IDE to work with the project directory
10. **Backup Strategy**: Backup your project directories regularly

## 🔄 Recent Improvements

### File Accessibility Enhancement
- **Direct Host Access**: Laravel files are now directly accessible in `/var/www/copilot-infra/PROJECT_NAME/`
- **Bind Mount Architecture**: Uses bind mounts instead of Docker volumes for file access
- **Real-time Editing**: Changes to files are immediately reflected in the running application
- **IDE Integration**: Full support for IDEs and editors with syntax highlighting and debugging
- **No Container Rebuilds**: Edit code without needing to rebuild or restart containers

### Virtual Host Implementation
- **New Feature**: Complete virtual host support with reverse proxy
- **Automatic Routing**: nginx-proxy handles virtual host routing automatically
- **Smart Port Detection**: Automatically finds available ports to avoid conflicts
- **Hosts Management**: Built-in tools for managing `/etc/hosts` entries
- **Shared Infrastructure**: One proxy serves all projects efficiently

### Enhanced Project Management
- **Simplified Commands**: No more port management, just project names
- **Better Isolation**: Each project gets its own containers and network
- **Improved Cleanup**: Comprehensive cleanup including hosts entries
- **Status Monitoring**: Enhanced status reporting with virtual host info

### Developer Experience
- **Easy Access**: Simple `.loc` domains instead of port numbers
- **Multiple Projects**: Run unlimited projects simultaneously
- **Quick Setup**: One command creates everything needed
- **Automated Management**: Scripts handle complex configurations
- **File Editing**: Direct access to all Laravel files for development

## 📝 Available Make Commands

```bash
make help           # Show all available commands
make init           # Initialize a new Laravel project
make status         # Check project status
make clean          # Remove project completely
make add-host       # Add virtual host to /etc/hosts
make remove-host    # Remove virtual host from /etc/hosts
make list-hosts     # List all virtual host entries
make clean-proxy    # Remove shared reverse proxy
make hosts-help     # Show hosts file management help
```

## 📝 License

This project is open source and available under the MIT License.

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## Support

For issues and questions:
1. Check the troubleshooting section
2. Review Docker and Laravel documentation
3. Open an issue with detailed error information 