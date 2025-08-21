#!/bin/bash

echo "FriendlyPOS Print Server - Deployment Script"
echo "==========================================="

TARGET=${1:-root@192.168.1.1}
REMOTE_DIR="/usr/local/friendlypos"
LOCAL_DIR="$(cd "$(dirname "$0")/.." && pwd)"

usage() {
    echo "Usage: $0 [user@host] [options]"
    echo ""
    echo "Options:"
    echo "  --install    First-time installation"
    echo "  --update     Update existing installation (default)"
    echo "  --restart    Just restart the service"
    echo "  --logs       Show recent logs"
    echo "  --status     Show service status"
    echo ""
    echo "Examples:"
    echo "  $0 root@192.168.1.1 --install"
    echo "  $0 root@192.168.1.1 --update"
    echo "  $0 root@192.168.1.1 --logs"
    exit 1
}

check_connection() {
    echo "Testing connection to $TARGET..."
    if ssh -o ConnectTimeout=5 -o BatchMode=yes $TARGET "echo 'Connected'" &>/dev/null; then
        echo "✓ Connection successful"
        return 0
    else
        echo "✗ Failed to connect to $TARGET"
        echo "Make sure:"
        echo "  1. The router is powered on and connected"
        echo "  2. SSH is enabled on the router"
        echo "  3. You have the correct IP address"
        echo "  4. SSH keys are configured or password auth is enabled"
        exit 1
    fi
}

install_first_time() {
    echo "Installing FriendlyPOS Print Server for the first time..."
    
    ssh $TARGET "opkg update && opkg install python3-light python3-logging" || {
        echo "Failed to install Python packages"
        exit 1
    }
    
    ssh $TARGET "mkdir -p $REMOTE_DIR"
    
    echo "Copying files..."
    scp -r $LOCAL_DIR/print_server.py \
           $LOCAL_DIR/config.env.example \
           $LOCAL_DIR/init.d/print_server \
           $TARGET:$REMOTE_DIR/ || {
        echo "Failed to copy files"
        exit 1
    }
    
    ssh $TARGET "chmod +x $REMOTE_DIR/print_server.py"
    
    ssh $TARGET "cp $REMOTE_DIR/print_server /etc/init.d/ && chmod +x /etc/init.d/print_server"
    
    ssh $TARGET << 'EOF'
        if [ ! -f /usr/local/friendlypos/config.env ]; then
            cp /usr/local/friendlypos/config.env.example /usr/local/friendlypos/config.env
            echo ""
            echo "IMPORTANT: Configuration needed!"
            echo "1. SSH into the router: ssh root@192.168.1.1"
            echo "2. Edit the configuration: vi /usr/local/friendlypos/config.env"
            echo "3. Add your API credentials and printer IPs"
            echo "4. Enable the service: /etc/init.d/print_server enable"
            echo "5. Start the service: /etc/init.d/print_server start"
        fi
EOF
    
    echo ""
    echo "Installation complete!"
    echo ""
    echo "Next steps:"
    echo "1. SSH into router: ssh $TARGET"
    echo "2. Configure: vi $REMOTE_DIR/config.env"
    echo "3. Enable service: /etc/init.d/print_server enable"
    echo "4. Start service: /etc/init.d/print_server start"
}

update_installation() {
    echo "Updating FriendlyPOS Print Server..."
    
    echo "Backing up current configuration..."
    ssh $TARGET "cp $REMOTE_DIR/config.env /tmp/config.env.backup 2>/dev/null"
    
    echo "Copying updated files..."
    scp $LOCAL_DIR/print_server.py $TARGET:$REMOTE_DIR/ || {
        echo "Failed to copy print_server.py"
        exit 1
    }
    
    if [ -f $LOCAL_DIR/init.d/print_server ]; then
        scp $LOCAL_DIR/init.d/print_server $TARGET:/etc/init.d/ || {
            echo "Failed to copy init script"
        }
        ssh $TARGET "chmod +x /etc/init.d/print_server"
    fi
    
    echo "Restarting service..."
    ssh $TARGET "/etc/init.d/print_server restart" || {
        echo "Note: Service restart failed (might not be running)"
    }
    
    echo ""
    echo "Update complete!"
    show_status
}

restart_service() {
    echo "Restarting print server..."
    ssh $TARGET "/etc/init.d/print_server restart"
    sleep 2
    show_status
}

show_logs() {
    echo "Recent logs from print server:"
    echo "=============================="
    ssh $TARGET "tail -n 50 /tmp/print_server.log 2>/dev/null || echo 'No logs found'"
    echo ""
    echo "To follow logs in real-time:"
    echo "  ssh $TARGET 'tail -f /tmp/print_server.log'"
}

show_status() {
    echo "Service status:"
    echo "=============="
    ssh $TARGET "/etc/init.d/print_server status 2>/dev/null || echo 'Service not found'"
    echo ""
    
    ssh $TARGET "ps | grep -v grep | grep print_server" &>/dev/null
    if [ $? -eq 0 ]; then
        echo "✓ Print server is running"
        ssh $TARGET "ps | grep -v grep | grep print_server"
    else
        echo "✗ Print server is not running"
    fi
    echo ""
    
    echo "Configuration status:"
    ssh $TARGET "[ -f $REMOTE_DIR/config.env ] && echo '✓ config.env exists' || echo '✗ config.env missing'"
    
    echo ""
    echo "Recent log entries:"
    ssh $TARGET "tail -n 5 /tmp/print_server.log 2>/dev/null | head -5"
}

ACTION=${2:---update}

if [ "$1" == "--help" ] || [ "$1" == "-h" ]; then
    usage
fi

if [[ "$1" == --* ]]; then
    ACTION=$1
    TARGET="root@192.168.1.1"
fi

check_connection

case $ACTION in
    --install)
        install_first_time
        ;;
    --update)
        update_installation
        ;;
    --restart)
        restart_service
        ;;
    --logs)
        show_logs
        ;;
    --status)
        show_status
        ;;
    *)
        echo "Unknown action: $ACTION"
        usage
        ;;
esac