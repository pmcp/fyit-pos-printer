#!/bin/sh

echo "FriendlyPOS Print Server - OpenWrt Installation"
echo "=============================================="

INSTALL_DIR="/usr/local/friendlypos"

check_root() {
    if [ "$(id -u)" != "0" ]; then
        echo "Error: This script must be run as root"
        exit 1
    fi
}

check_openwrt() {
    if [ ! -f /etc/openwrt_release ]; then
        echo "Warning: This doesn't appear to be an OpenWrt system"
        echo "Continue anyway? (y/n): "
        read answer
        if [ "$answer" != "y" ]; then
            exit 1
        fi
    else
        . /etc/openwrt_release
        echo "Detected: $DISTRIB_DESCRIPTION"
    fi
}

install_dependencies() {
    echo "Updating package list..."
    opkg update || {
        echo "Failed to update package list"
        echo "Check your internet connection"
        exit 1
    }
    
    echo "Installing Python and required packages..."
    
    PACKAGES="python3-light python3-logging python3-urllib python3-email python3-codecs"
    
    for pkg in $PACKAGES; do
        echo "Installing $pkg..."
        opkg install $pkg || {
            echo "Warning: Failed to install $pkg"
        }
    done
}

create_directories() {
    echo "Creating application directories..."
    mkdir -p $INSTALL_DIR
    mkdir -p /var/log
    mkdir -p /var/run
}

install_files() {
    echo "Installing application files..."
    
    if [ -f print_server.py ]; then
        cp print_server.py $INSTALL_DIR/
        chmod +x $INSTALL_DIR/print_server.py
        echo "✓ Installed print_server.py"
    else
        echo "✗ print_server.py not found"
    fi
    
    if [ -f config.env.example ]; then
        cp config.env.example $INSTALL_DIR/
        echo "✓ Installed config.env.example"
        
        if [ ! -f $INSTALL_DIR/config.env ]; then
            cp $INSTALL_DIR/config.env.example $INSTALL_DIR/config.env
            echo "✓ Created config.env from template"
        fi
    fi
    
    if [ -f init.d/print_server ]; then
        cp init.d/print_server /etc/init.d/
        chmod +x /etc/init.d/print_server
        echo "✓ Installed init.d service script"
    else
        echo "✗ init.d/print_server not found"
    fi
}

configure_service() {
    echo "Configuring service..."
    
    /etc/init.d/print_server enable || {
        echo "Warning: Failed to enable service"
    }
    
    cat << 'EOF'

Service has been enabled for automatic startup.

To manage the service:
  Start:   /etc/init.d/print_server start
  Stop:    /etc/init.d/print_server stop
  Restart: /etc/init.d/print_server restart
  Status:  /etc/init.d/print_server status

EOF
}

configure_firewall() {
    echo "Checking firewall configuration..."
    
    if [ -f /etc/config/firewall ]; then
        echo "Do you want to add firewall rules for printer access? (y/n): "
        read answer
        
        if [ "$answer" = "y" ]; then
            cat << 'EOF' >> /etc/config/firewall

# FriendlyPOS Print Server - Allow printer communication
config rule
    option name 'Allow-Printer-9100'
    option src 'lan'
    option dest 'lan'
    option dest_port '9100'
    option proto 'tcp'
    option target 'ACCEPT'

EOF
            echo "✓ Firewall rules added"
            echo "Reloading firewall..."
            /etc/init.d/firewall reload
        fi
    fi
}

check_memory() {
    echo "Checking system resources..."
    
    TOTAL_MEM=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
    FREE_MEM=$(awk '/MemAvailable/ {print $2}' /proc/meminfo)
    
    if [ -z "$FREE_MEM" ]; then
        FREE_MEM=$(awk '/MemFree/ {print $2}' /proc/meminfo)
    fi
    
    echo "Total memory: $((TOTAL_MEM / 1024)) MB"
    echo "Available memory: $((FREE_MEM / 1024)) MB"
    
    if [ $TOTAL_MEM -lt 65536 ]; then
        echo "Warning: System has less than 64MB RAM"
        echo "Print server should still work but monitor memory usage"
    fi
    
    FLASH_SIZE=$(df -h /overlay 2>/dev/null | awk 'NR==2 {print $2}')
    FLASH_AVAIL=$(df -h /overlay 2>/dev/null | awk 'NR==2 {print $4}')
    
    if [ -n "$FLASH_SIZE" ]; then
        echo "Flash storage: $FLASH_AVAIL available of $FLASH_SIZE"
    fi
}

post_install_info() {
    cat << 'EOF'

===============================================
Installation Complete!
===============================================

IMPORTANT - Next Steps:

1. Configure the print server:
   vi /usr/local/friendlypos/config.env
   
   Required settings:
   - API_URL: Your FriendlyPOS API endpoint
   - API_KEY: Your API authentication key  
   - LOCATION_ID: Your location ID
   - PRINTER_*: Your printer IP addresses

2. Test printer connectivity:
   python3 /usr/local/friendlypos/print_server.py

3. Start the service:
   /etc/init.d/print_server start

4. Check logs:
   tail -f /tmp/print_server.log

5. Verify service is running:
   ps | grep print_server

===============================================

For troubleshooting:
- Logs: /tmp/print_server.log
- Config: /usr/local/friendlypos/config.env
- Service: /etc/init.d/print_server

EOF
}

main() {
    check_root
    check_openwrt
    
    echo ""
    echo "This will install FriendlyPOS Print Server on your router"
    echo "Continue? (y/n): "
    read answer
    
    if [ "$answer" != "y" ]; then
        echo "Installation cancelled"
        exit 0
    fi
    
    install_dependencies
    create_directories
    install_files
    configure_service
    configure_firewall
    check_memory
    post_install_info
}

main "$@"