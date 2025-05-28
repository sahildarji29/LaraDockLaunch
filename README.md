# Laravel Container Initialization with Virtual Hosts

A robust shell script and Makefile system for quickly setting up Laravel projects with Docker containers using virtual host configuration. This tool automatically creates a complete Laravel development environment with PHP-FPM, Nginx, and a reverse proxy for seamless virtual host routing.

## ✨ Features

- **Virtual Host Support**: Access projects via custom domains (e.g., `myapp.loc`)
- **One-command Laravel setup**: Initialize a complete Laravel project with Docker containers
- **Automatic Laravel installation**: Downloads and configures Laravel directly in the container
- **Reverse Proxy**: Shared Nginx proxy for handling multiple virtual hosts
- **Volume-based persistence**: Project files are stored in Docker volumes for better performance
- **Health checks**: Proper container health monitoring and startup verification
- **Hosts file management**: Built-in tools for managing `/etc/hosts` entries
- **Error handling**: Comprehensive error checking and graceful failure handling
- **Project management**: Easy cleanup and status checking for projects
- **Dependency validation**: Checks for Docker and Docker Compose before starting

## 🔧 Prerequisites

- Docker (with daemon running)
- Docker Compose
- Make (for using the Makefile)
- Bash shell
- Sudo access (for managing `/etc/hosts` file)

## 🚀 Quick Start

### Initialize a new Laravel project
```bash
make init PROJECT_NAME=my-app
```

### Add virtual host to your system
```bash
make add-host PROJECT_NAME=my-app
# or manually: ./manage-hosts.sh add my-app
```

### Access your application
Visit `http://my-app.loc` in your browser

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

### Basic project creation with virtual host
```bash
# Create the project
make init PROJECT_NAME=blog

# Add to hosts file
make add-host PROJECT_NAME=blog

# Visit http://blog.loc
```

### Multiple projects
```bash
# Create multiple projects
make init PROJECT_NAME=api
make init PROJECT_NAME=frontend
make init PROJECT_NAME=admin

# Add all to hosts file
make add-host PROJECT_NAME=api
make add-host PROJECT_NAME=frontend  
make add-host PROJECT_NAME=admin

# Access at:
# http://api.loc
# http://frontend.loc
# http://admin.loc
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
/var/www/PROJECT_NAME/
├── Dockerfile              # PHP-FPM container with Laravel dependencies
├── docker-compose.yml      # Container orchestration
└── nginx.conf             # Nginx configuration for virtual host

Docker Resources:
├── PROJECT_NAME_php        # PHP-FPM container
├── PROJECT_NAME_nginx      # Nginx container for the project
├── laravel_proxy           # Shared reverse proxy (created once)
├── PROJECT_NAME_volume     # Persistent volume for Laravel files
├── PROJECT_NAME_net        # Project network
└── laravel_proxy_net       # Shared proxy network
```

## 🌐 Virtual Host Architecture

### Reverse Proxy Setup
- **Shared Proxy**: One `laravel_proxy` container handles all virtual hosts
- **Automatic Discovery**: Uses `nginxproxy/nginx-proxy` for automatic configuration
- **Port 80**: All traffic goes through the proxy on port 80
- **Domain Routing**: Routes requests based on `Host` header

### Virtual Host Configuration
- **Pattern**: `PROJECT_NAME.loc` (e.g., `myapp.loc`, `blog.loc`)
- **Local Resolution**: Uses `/etc/hosts` file for local domain resolution
- **SSL Ready**: Can be extended with SSL certificates if needed

## 🔍 Technical Details

### Container Architecture
- **PHP Container**: PHP 8.3-FPM with Composer, Laravel dependencies
- **Nginx Container**: Project-specific Nginx with virtual host configuration
- **Reverse Proxy**: Shared nginx-proxy container for routing
- **Volume Management**: Docker volumes for persistent file storage
- **Network Isolation**: Projects connected via shared proxy network

### Laravel Installation Process
1. Creates a clean Docker volume
2. Sets up proxy network if not exists
3. Installs Laravel in a temporary directory inside the container
4. Moves Laravel files to the volume root
5. Sets proper permissions and ownership
6. Configures environment and generates application key
7. Connects to reverse proxy for virtual host routing
8. Verifies installation with health checks

### Hosts File Management
The included `manage-hosts.sh` script provides:
- **Add entries**: `./manage-hosts.sh add PROJECT_NAME`
- **Remove entries**: `./manage-hosts.sh remove PROJECT_NAME`
- **List entries**: `./manage-hosts.sh list`
- **Automatic validation**: Checks for existing entries

## 🛠️ Advanced Usage

### Direct script usage
```bash
./init-laravel-container.sh project_name /var/www volume_name
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
docker exec PROJECT_NAME_php php /var/www/artisan migrate
docker exec PROJECT_NAME_php php /var/www/artisan make:controller HomeController
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

**Port 80 already in use**
- Stop conflicting services: `sudo systemctl stop apache2 nginx`
- Check what's using port 80: `sudo netstat -tulpn | grep :80`
- Kill the proxy and restart: `make clean-proxy && make init PROJECT_NAME=test`

**Permission issues with hosts file**
- Ensure you have sudo access
- Check hosts file permissions: `ls -la /etc/hosts`
- Use the manual commands if script fails

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

# Force remove volumes  
docker volume rm PROJECT_NAME_volume --force

# Remove networks
docker network rm PROJECT_NAME_net

# Remove project directory
rm -rf /var/www/PROJECT_NAME

# Clean up hosts entry
./manage-hosts.sh remove PROJECT_NAME
```

## 🎯 Best Practices

1. **Use descriptive project names**: Helps identify projects and virtual hosts
2. **Consistent naming**: Use lowercase, hyphens for multi-word projects
3. **Regular cleanup**: Remove unused projects and hosts entries
4. **Monitor proxy**: Keep an eye on the shared proxy container
5. **Backup important data**: Volume data persists but backup critical work
6. **Hosts file management**: Use the provided scripts for consistency

## 🔄 Recent Improvements

### Virtual Host Implementation
- **New Feature**: Complete virtual host support with reverse proxy
- **Automatic Routing**: nginx-proxy handles virtual host routing automatically
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