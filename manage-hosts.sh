#!/bin/bash

# Script to manage /etc/hosts entries for Laravel virtual hosts

HOSTS_FILE="/etc/hosts"

show_help() {
    echo "Laravel Virtual Host Manager"
    echo "============================"
    echo ""
    echo "Usage: $0 <command> <project_name>"
    echo ""
    echo "Commands:"
    echo "  add <project_name>     - Add virtual host entry for project"
    echo "  remove <project_name>  - Remove virtual host entry for project"
    echo "  list                   - List all Laravel virtual host entries"
    echo "  help                   - Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 add myapp           # Adds: 127.0.0.1 myapp.loc"
    echo "  $0 remove myapp        # Removes the myapp.loc entry"
    echo "  $0 list                # Shows all .loc entries"
}

add_host() {
    local project_name=$1
    local virtual_host="${project_name}.loc"
    
    if [ -z "$project_name" ]; then
        echo "❌ Project name is required"
        echo "Usage: $0 add <project_name>"
        exit 1
    fi
    
    # Check if entry already exists
    if grep -q "127.0.0.1.*${virtual_host}" "$HOSTS_FILE" 2>/dev/null; then
        echo "⚠️  Entry for ${virtual_host} already exists in $HOSTS_FILE"
        return 0
    fi
    
    # Add entry
    echo "127.0.0.1 ${virtual_host}" | sudo tee -a "$HOSTS_FILE" > /dev/null
    
    if [ $? -eq 0 ]; then
        echo "✅ Added virtual host: ${virtual_host}"
        echo "🌐 You can now access your project at: http://${virtual_host}"
    else
        echo "❌ Failed to add virtual host entry"
        exit 1
    fi
}

remove_host() {
    local project_name=$1
    local virtual_host="${project_name}.loc"
    
    if [ -z "$project_name" ]; then
        echo "❌ Project name is required"
        echo "Usage: $0 remove <project_name>"
        exit 1
    fi
    
    # Check if entry exists
    if ! grep -q "127.0.0.1.*${virtual_host}" "$HOSTS_FILE" 2>/dev/null; then
        echo "⚠️  No entry found for ${virtual_host} in $HOSTS_FILE"
        return 0
    fi
    
    # Remove entry
    sudo sed -i "/127\.0\.0\.1.*${virtual_host}/d" "$HOSTS_FILE"
    
    if [ $? -eq 0 ]; then
        echo "✅ Removed virtual host: ${virtual_host}"
    else
        echo "❌ Failed to remove virtual host entry"
        exit 1
    fi
}

list_hosts() {
    echo "📋 Laravel Virtual Host Entries:"
    echo "================================"
    
    local entries=$(grep "127\.0\.0\.1.*\.loc" "$HOSTS_FILE" 2>/dev/null)
    
    if [ -z "$entries" ]; then
        echo "No Laravel virtual host entries found."
    else
        echo "$entries"
    fi
}

# Main script logic
case "$1" in
    "add")
        add_host "$2"
        ;;
    "remove")
        remove_host "$2"
        ;;
    "list")
        list_hosts
        ;;
    "help"|"--help"|"-h"|"")
        show_help
        ;;
    *)
        echo "❌ Unknown command: $1"
        echo ""
        show_help
        exit 1
        ;;
esac 