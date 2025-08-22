#!/bin/sh

# Uses RUT956's native print server - handles all queuing automatically!
# The router's print server manages timing, buffers, and prevents corruption

API_KEY="d5a8262b7cfd8f46e599b36c584bb1ec16f28436680ddaa53f700e6d8a1765fa"
LOGFILE="/tmp/print.log"
LAST_ID="/tmp/last_id"

# Print to localhost since we're ON the router
# The RUT956 print server listens on port 9100
PRINTER_PORT="127.0.0.1:9100"

# Ensure DNS
grep -q "8.8.8.8" /etc/resolv.conf || echo "nameserver 8.8.8.8" >> /etc/resolv.conf

echo "$(date '+%H:%M:%S') Native print server client started" >> "$LOGFILE"

# Setup instructions
echo "=== SETUP REQUIRED ===" >> "$LOGFILE"
echo "1. Connect printer to RUT956 USB port" >> "$LOGFILE"
echo "2. Enable in WebUI: Services → USB Tools → Printer Server" >> "$LOGFILE"
echo "3. Set port to 9100 (default)" >> "$LOGFILE"
echo "====================" >> "$LOGFILE"

while true; do
    # Fetch print jobs
    R=$(curl -s -m 5 -k -H "Authorization: Bearer $API_KEY" "https://friendlypos.vercel.app/api/print-queue" 2>/dev/null)
    
    if [ ! -z "$R" ] && echo "$R" | grep -q '"printData"'; then
        # Extract ID
        ID=$(echo "$R" | sed -n 's/.*"id":"\([^"]*\)".*/\1/p')
        [ -z "$ID" ] && ID="$(date +%s)"
        
        # Skip duplicates
        [ -f "$LAST_ID" ] && [ "$ID" = "$(cat $LAST_ID)" ] && { sleep 1; continue; }
        
        # Extract data
        DATA=$(echo "$R" | sed -n 's/.*"printData":"\([^"]*\)".*/\1/p')
        
        if [ ! -z "$DATA" ]; then
            echo "$(date '+%H:%M:%S') Sending job $ID to native print server" >> "$LOGFILE"
            
            # Send to native print server - it handles ALL timing/queuing!
            echo "$DATA" | base64 -d | nc 127.0.0.1 9100
            
            if [ $? -eq 0 ]; then
                echo "$(date '+%H:%M:%S') Job $ID queued successfully" >> "$LOGFILE"
                echo "$ID" > "$LAST_ID"
            else
                echo "$(date '+%H:%M:%S') Failed - is print server enabled?" >> "$LOGFILE"
            fi
        fi
    fi
    
    # Poll API every second - print server handles the rest
    sleep 1
done