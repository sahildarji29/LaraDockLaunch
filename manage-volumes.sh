#!/bin/bash

# Volume Management Script for High-Scale Laravel Deployment
# Manages named Docker volumes for data persistence

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to display usage
show_help() {
    echo "Volume Management for High-Scale Laravel Deployment"
    echo "=================================================="
    echo ""
    echo "Usage: $0 <command> [options]"
    echo ""
    echo "Commands:"
    echo "  list                     List all project volumes"
    echo "  backup <project_name>    Backup project data to tar file"
    echo "  restore <project_name>   Restore project data from tar file"
    echo "  copy <src> <dest>        Copy data from one project to another"
    echo "  inspect <project_name>   Show detailed volume information"
    echo "  cleanup                  Remove unused volumes"
    echo "  size                     Show volume sizes"
    echo "  export <project_name>    Export project files to host directory"
    echo "  import <project_name>    Import host directory to project volume"
    echo ""
    echo "Examples:"
    echo "  $0 list                          # List all volumes"
    echo "  $0 backup myapp                  # Backup myapp data"
    echo "  $0 restore myapp                 # Restore myapp data"
    echo "  $0 copy myapp myapp-staging      # Copy myapp to myapp-staging"
    echo "  $0 export myapp /tmp/myapp-files # Export files to host"
    echo "  $0 import myapp /tmp/myapp-files # Import files from host"
    echo ""
    echo "Data Persistence Benefits:"
    echo "  • Data survives container restarts"
    echo "  • Isolated storage per project"
    echo "  • Easy backup and restore"
    echo "  • Better security than bind mounts"
    echo "  • Optimized for high-scale deployment"
}

# Function to check if Docker is running
check_docker() {
    if ! docker info >/dev/null 2>&1; then
        echo -e "${RED}❌ Docker is not running${NC}"
        exit 1
    fi
}

# Function to list all project volumes
list_volumes() {
    echo -e "${BLUE}📋 Project Volumes:${NC}"
    echo ""
    echo "Data Volumes:"
    docker volume ls --filter "name=_data" --format "table {{.Driver}}\t{{.Name}}\t{{.Scope}}" | grep -E "(_data|DRIVER)" || echo "No project data volumes found"
    echo ""
    echo "Log Volumes:"
    docker volume ls --filter "name=_logs" --format "table {{.Driver}}\t{{.Name}}\t{{.Scope}}" | grep -E "(_logs|DRIVER)" || echo "No project log volumes found"
    echo ""
    echo -e "${BLUE}📊 Volume Statistics:${NC}"
    local total_data_volumes=$(docker volume ls --filter "name=_data" --format "{{.Name}}" | wc -l)
    local total_log_volumes=$(docker volume ls --filter "name=_logs" --format "{{.Name}}" | wc -l)
    echo "Total project data volumes: $total_data_volumes"
    echo "Total project log volumes: $total_log_volumes"
    echo "Total project volumes: $((total_data_volumes + total_log_volumes))"
}

# Function to backup project data
backup_project() {
    local project_name=$1
    local data_volume="${project_name}_data"
    local logs_volume="${project_name}_logs"
    local backup_file="${project_name}_backup_$(date +%Y%m%d_%H%M%S).tar.gz"
    
    if [ -z "$project_name" ]; then
        echo -e "${RED}❌ Please specify project name${NC}"
        echo "Usage: $0 backup <project_name>"
        exit 1
    fi
    
    # Check if data volume exists
    if ! docker volume inspect "$data_volume" >/dev/null 2>&1; then
        echo -e "${RED}❌ Data volume '$data_volume' does not exist${NC}"
        exit 1
    fi
    
    echo -e "${BLUE}💾 Backing up project: $project_name${NC}"
    echo "Data volume: $data_volume"
    if docker volume inspect "$logs_volume" >/dev/null 2>&1; then
        echo "Logs volume: $logs_volume"
    fi
    echo "Backup file: $backup_file"
    
    # Create backup using temporary container
    if docker volume inspect "$logs_volume" >/dev/null 2>&1; then
        # Backup both data and logs
        docker run --rm \
            -v "$data_volume:/data" \
            -v "$logs_volume:/logs" \
            -v "$(pwd):/backup" \
            alpine:latest \
            sh -c "cd / && tar -czf /backup/$backup_file data logs"
    else
        # Backup only data volume
        docker run --rm \
            -v "$data_volume:/data" \
            -v "$(pwd):/backup" \
            alpine:latest \
            tar -czf "/backup/$backup_file" -C /data .
    fi
    
    echo -e "${GREEN}✅ Backup completed: $backup_file${NC}"
    echo "Size: $(du -h "$backup_file" | cut -f1)"
}

# Function to restore project data
restore_project() {
    local project_name=$1
    local data_volume="${project_name}_data"
    local logs_volume="${project_name}_logs"
    local backup_file="${project_name}_backup_*.tar.gz"
    
    if [ -z "$project_name" ]; then
        echo -e "${RED}❌ Please specify project name${NC}"
        echo "Usage: $0 restore <project_name>"
        exit 1
    fi
    
    # Find latest backup file
    local latest_backup=$(ls -t ${project_name}_backup_*.tar.gz 2>/dev/null | head -1)
    if [ -z "$latest_backup" ]; then
        echo -e "${RED}❌ No backup file found for project: $project_name${NC}"
        echo "Expected pattern: ${project_name}_backup_*.tar.gz"
        exit 1
    fi
    
    echo -e "${BLUE}🔄 Restoring project: $project_name${NC}"
    echo "Data volume: $data_volume"
    echo "Logs volume: $logs_volume"
    echo "Backup file: $latest_backup"
    
    # Create volumes if they don't exist
    if ! docker volume inspect "$data_volume" >/dev/null 2>&1; then
        echo "Creating data volume: $data_volume"
        docker volume create "$data_volume"
    fi
    
    if ! docker volume inspect "$logs_volume" >/dev/null 2>&1; then
        echo "Creating logs volume: $logs_volume"
        docker volume create "$logs_volume"
    fi
    
    # Check if backup contains both data and logs
    if tar -tzf "$latest_backup" | grep -q "^logs/"; then
        echo "Restoring data and logs..."
        # Restore both data and logs
        docker run --rm \
            -v "$data_volume:/data" \
            -v "$logs_volume:/logs" \
            -v "$(pwd):/backup" \
            alpine:latest \
            sh -c "cd / && tar -xzf /backup/$latest_backup"
    else
        echo "Restoring data only..."
        # Restore only data (legacy backup format)
        docker run --rm \
            -v "$data_volume:/data" \
            -v "$(pwd):/backup" \
            alpine:latest \
            tar -xzf "/backup/$latest_backup" -C /data
    fi
    
    echo -e "${GREEN}✅ Restore completed from: $latest_backup${NC}"
}

# Function to copy data from one project to another
copy_project() {
    local src_project=$1
    local dest_project=$2
    local src_volume="${src_project}_data"
    local dest_volume="${dest_project}_data"
    
    if [ -z "$src_project" ] || [ -z "$dest_project" ]; then
        echo -e "${RED}❌ Please specify both source and destination projects${NC}"
        echo "Usage: $0 copy <source_project> <destination_project>"
        exit 1
    fi
    
    # Check if source volume exists
    if ! docker volume inspect "$src_volume" >/dev/null 2>&1; then
        echo -e "${RED}❌ Source volume '$src_volume' does not exist${NC}"
        exit 1
    fi
    
    echo -e "${BLUE}📋 Copying project data:${NC}"
    echo "From: $src_project ($src_volume)"
    echo "To: $dest_project ($dest_volume)"
    
    # Create destination volume if it doesn't exist
    if ! docker volume inspect "$dest_volume" >/dev/null 2>&1; then
        echo "Creating destination volume: $dest_volume"
        docker volume create "$dest_volume"
    fi
    
    # Copy data using temporary container
    docker run --rm \
        -v "$src_volume:/source" \
        -v "$dest_volume:/destination" \
        alpine:latest \
        sh -c "cd /source && tar -cf - . | (cd /destination && tar -xf -)"
    
    echo -e "${GREEN}✅ Copy completed successfully${NC}"
}

# Function to inspect volume
inspect_volume() {
    local project_name=$1
    local volume_name="${project_name}_data"
    
    if [ -z "$project_name" ]; then
        echo -e "${RED}❌ Please specify project name${NC}"
        echo "Usage: $0 inspect <project_name>"
        exit 1
    fi
    
    # Check if volume exists
    if ! docker volume inspect "$volume_name" >/dev/null 2>&1; then
        echo -e "${RED}❌ Volume '$volume_name' does not exist${NC}"
        exit 1
    fi
    
    echo -e "${BLUE}🔍 Volume Information: $volume_name${NC}"
    echo ""
    docker volume inspect "$volume_name"
    echo ""
    
    # Show volume usage
    echo -e "${BLUE}📊 Volume Usage:${NC}"
    docker run --rm \
        -v "$volume_name:/data" \
        alpine:latest \
        sh -c "df -h /data && echo '' && du -sh /data/* 2>/dev/null || echo 'No files found'"
}

# Function to cleanup unused volumes
cleanup_volumes() {
    echo -e "${YELLOW}🧹 Cleaning up unused volumes...${NC}"
    
    # List volumes that would be removed
    local unused_volumes=$(docker volume ls --filter "dangling=true" --format "{{.Name}}")
    
    if [ -z "$unused_volumes" ]; then
        echo -e "${GREEN}✅ No unused volumes found${NC}"
        return 0
    fi
    
    echo "Unused volumes found:"
    echo "$unused_volumes"
    echo ""
    
    read -p "Remove these volumes? (y/N): " -n 1 -r
    echo ""
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        docker volume prune -f
        echo -e "${GREEN}✅ Unused volumes removed${NC}"
    else
        echo -e "${YELLOW}❌ Cleanup cancelled${NC}"
    fi
}

# Function to show volume sizes
show_sizes() {
    echo -e "${BLUE}📊 Volume Sizes:${NC}"
    echo ""
    
    local volumes=$(docker volume ls --filter "name=_data" --format "{{.Name}}")
    
    if [ -z "$volumes" ]; then
        echo "No project volumes found"
        return 0
    fi
    
    printf "%-20s %-10s\n" "Project" "Size"
    printf "%-20s %-10s\n" "-------" "----"
    
    for volume in $volumes; do
        local project=$(echo "$volume" | sed 's/_data$//')
        local size=$(docker run --rm -v "$volume:/data" alpine:latest du -sh /data 2>/dev/null | cut -f1)
        printf "%-20s %-10s\n" "$project" "$size"
    done
}

# Function to export project files to host
export_project() {
    local project_name=$1
    local host_dir=$2
    local volume_name="${project_name}_data"
    
    if [ -z "$project_name" ] || [ -z "$host_dir" ]; then
        echo -e "${RED}❌ Please specify project name and host directory${NC}"
        echo "Usage: $0 export <project_name> <host_directory>"
        exit 1
    fi
    
    # Check if volume exists
    if ! docker volume inspect "$volume_name" >/dev/null 2>&1; then
        echo -e "${RED}❌ Volume '$volume_name' does not exist${NC}"
        exit 1
    fi
    
    echo -e "${BLUE}📤 Exporting project: $project_name${NC}"
    echo "Volume: $volume_name"
    echo "Host directory: $host_dir"
    
    # Create host directory if it doesn't exist
    mkdir -p "$host_dir"
    
    # Export data using temporary container
    docker run --rm \
        -v "$volume_name:/data" \
        -v "$host_dir:/host" \
        alpine:latest \
        sh -c "cd /data && cp -r * /host/ 2>/dev/null || echo 'No files to copy'"
    
    echo -e "${GREEN}✅ Export completed to: $host_dir${NC}"
}

# Function to import host directory to project volume
import_project() {
    local project_name=$1
    local host_dir=$2
    local volume_name="${project_name}_data"
    
    if [ -z "$project_name" ] || [ -z "$host_dir" ]; then
        echo -e "${RED}❌ Please specify project name and host directory${NC}"
        echo "Usage: $0 import <project_name> <host_directory>"
        exit 1
    fi
    
    # Check if host directory exists
    if [ ! -d "$host_dir" ]; then
        echo -e "${RED}❌ Host directory '$host_dir' does not exist${NC}"
        exit 1
    fi
    
    echo -e "${BLUE}📥 Importing to project: $project_name${NC}"
    echo "Volume: $volume_name"
    echo "Host directory: $host_dir"
    
    # Create volume if it doesn't exist
    if ! docker volume inspect "$volume_name" >/dev/null 2>&1; then
        echo "Creating volume: $volume_name"
        docker volume create "$volume_name"
    fi
    
    # Import data using temporary container
    docker run --rm \
        -v "$volume_name:/data" \
        -v "$host_dir:/host" \
        alpine:latest \
        sh -c "cd /host && cp -r * /data/ 2>/dev/null || echo 'No files to copy'"
    
    echo -e "${GREEN}✅ Import completed from: $host_dir${NC}"
}

# Main script logic
case "$1" in
    "list")
        check_docker
        list_volumes
        ;;
    "backup")
        check_docker
        backup_project "$2"
        ;;
    "restore")
        check_docker
        restore_project "$2"
        ;;
    "copy")
        check_docker
        copy_project "$2" "$3"
        ;;
    "inspect")
        check_docker
        inspect_volume "$2"
        ;;
    "cleanup")
        check_docker
        cleanup_volumes
        ;;
    "size")
        check_docker
        show_sizes
        ;;
    "export")
        check_docker
        export_project "$2" "$3"
        ;;
    "import")
        check_docker
        import_project "$2" "$3"
        ;;
    *)
        show_help
        ;;
esac 