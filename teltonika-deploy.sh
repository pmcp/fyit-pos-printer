#!/bin/sh
# Deployment commands for Teltonika router (no nohup available)

echo "=== Teltonika Print Server Deployment ==="
echo ""
echo "Option 1: Run in background with output redirection"
echo "----------------------------------------------------"
echo "/root/print_server_fixed.sh > /dev/null 2>&1 &"
echo ""

echo "Option 2: Run with screen (if available)"
echo "-----------------------------------------"
echo "screen -dmS printserver /root/print_server_fixed.sh"
echo ""

echo "Option 3: Run directly in background"
echo "-------------------------------------"
echo "/root/print_server_fixed.sh &"
echo ""

echo "Option 4: Create a simple service script"
echo "-----------------------------------------"
cat << 'EOF'
# Create service file:
cat > /etc/init.d/printserver << 'SCRIPT'
#!/bin/sh /etc/rc.common
START=99
STOP=10

start() {
    echo "Starting print server..."
    /root/print_server_fixed.sh > /dev/null 2>&1 &
    echo $! > /var/run/printserver.pid
}

stop() {
    echo "Stopping print server..."
    if [ -f /var/run/printserver.pid ]; then
        kill $(cat /var/run/printserver.pid)
        rm /var/run/printserver.pid
    else
        killall print_server_fixed.sh 2>/dev/null
    fi
}

restart() {
    stop
    sleep 1
    start
}
SCRIPT

chmod +x /etc/init.d/printserver

# Enable and start:
/etc/init.d/printserver enable
/etc/init.d/printserver start
EOF

echo ""
echo "=== Quick Start Commands ==="
echo ""
echo "1. Make script executable:"
echo "   chmod +x /root/print_server_fixed.sh"
echo ""
echo "2. Kill old script if running:"
echo "   killall teltonika-print-server.sh 2>/dev/null"
echo "   killall print_server.sh 2>/dev/null"
echo ""
echo "3. Start new script in background:"
echo "   /root/print_server_fixed.sh &"
echo ""
echo "4. Check if running:"
echo "   ps | grep print_server"
echo ""
echo "5. Monitor logs:"
echo "   tail -f /tmp/printserver.log"
echo ""
echo "6. To stop:"
echo "   killall print_server_fixed.sh"