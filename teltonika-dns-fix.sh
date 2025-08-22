#!/bin/sh
# Fix DNS and API connectivity issues on Teltonika

echo "=== Fixing DNS and API Connectivity ==="
echo ""

# 1. Check current DNS settings
echo "Current DNS servers:"
cat /etc/resolv.conf
echo ""

# 2. Add Google DNS if not present
echo "Adding reliable DNS servers..."
if ! grep -q "8.8.8.8" /etc/resolv.conf; then
    echo "nameserver 8.8.8.8" >> /etc/resolv.conf
    echo "nameserver 8.8.4.4" >> /etc/resolv.conf
    echo "Added Google DNS servers"
fi

# 3. Test DNS resolution
echo ""
echo "Testing DNS resolution..."
nslookup friendlypos.vercel.app 8.8.8.8

# 4. Get IP address using different methods
echo ""
echo "Resolving friendlypos.vercel.app IP..."
IP=$(nslookup friendlypos.vercel.app 8.8.8.8 2>/dev/null | grep "Address" | tail -1 | awk '{print $3}')

if [ -z "$IP" ]; then
    # Fallback: Use host command if available
    IP=$(host friendlypos.vercel.app 8.8.8.8 2>/dev/null | grep "has address" | head -1 | awk '{print $4}')
fi

if [ -z "$IP" ]; then
    # Fallback: Use known Vercel IP range (this is less reliable)
    echo "Could not resolve, using Vercel IP directly..."
    IP="76.76.21.21"  # Vercel's anycast IP
fi

echo "Resolved IP: $IP"

# 5. Create updated print server script with DNS fixes
cat > /root/print_server_dns_fixed.sh << 'EOF'
#!/bin/sh

# Print server with DNS resilience
API_KEY="d5a8262b7cfd8f46e599b36c584bb1ec16f28436680ddaa53f700e6d8a1765fa"
PRINTER_IP="192.168.0.60"
LOGFILE="/tmp/printserver.log"

# Function to resolve hostname with fallback
resolve_host() {
    local host=$1
    local ip
    
    # Try nslookup with Google DNS
    ip=$(nslookup "$host" 8.8.8.8 2>/dev/null | grep "Address" | tail -1 | awk '{print $3}')
    
    if [ -z "$ip" ]; then
        # Try local DNS
        ip=$(nslookup "$host" 2>/dev/null | grep "Address" | tail -1 | awk '{print $3}')
    fi
    
    if [ -z "$ip" ]; then
        # Use hardcoded Vercel IP as last resort
        ip="76.76.21.21"
        echo "$(date '+%Y-%m-%d %H:%M:%S') WARNING: Using fallback IP $ip" >> "$LOGFILE"
    fi
    
    echo "$ip"
}

# Ensure DNS is configured
if ! grep -q "8.8.8.8" /etc/resolv.conf; then
    echo "nameserver 8.8.8.8" >> /etc/resolv.conf
    echo "nameserver 8.8.4.4" >> /etc/resolv.conf
fi

echo "$(date '+%Y-%m-%d %H:%M:%S') Starting print server with DNS fixes..." >> "$LOGFILE"

while true; do
    # Resolve API host
    API_HOST=$(resolve_host "friendlypos.vercel.app")
    
    # Fetch from API using resolved IP with Host header
    RESPONSE=$(curl -s -m 10 -k \
        -H "Host: friendlypos.vercel.app" \
        -H "Authorization: Bearer $API_KEY" \
        "https://$API_HOST/api/print-queue" 2>/dev/null)
    
    if [ $? -eq 0 ] && [ ! -z "$RESPONSE" ]; then
        # Check if response contains print data
        if echo "$RESPONSE" | grep -q '"printData"'; then
            
            # Extract base64 data
            PRINT_DATA=$(echo "$RESPONSE" | sed -n 's/.*"printData":"\([^"]*\)".*/\1/p')
            
            if [ ! -z "$PRINT_DATA" ]; then
                echo "$(date '+%Y-%m-%d %H:%M:%S') Received print job" >> "$LOGFILE"
                
                # Decode and send to printer
                echo "$PRINT_DATA" | base64 -d | nc -n -w 2 "$PRINTER_IP" 9100
                
                if [ $? -eq 0 ]; then
                    echo "$(date '+%Y-%m-%d %H:%M:%S') Print job sent successfully" >> "$LOGFILE"
                else
                    echo "$(date '+%Y-%m-%d %H:%M:%S') Failed to send to printer" >> "$LOGFILE"
                fi
            fi
        fi
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') API fetch failed (IP: $API_HOST)" >> "$LOGFILE"
    fi
    
    sleep 2
done
EOF

chmod +x /root/print_server_dns_fixed.sh

echo ""
echo "=== DNS Fix Complete ==="
echo ""
echo "To deploy the fixed script:"
echo "1. Kill old process: killall print_server_fixed.sh 2>/dev/null"
echo "2. Start new script: /root/print_server_dns_fixed.sh &"
echo "3. Monitor logs: tail -f /tmp/printserver.log"