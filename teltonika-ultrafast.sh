#!/bin/sh

# Ultra-fast print server - minimal delays, maximum throughput
# Only delays where absolutely necessary to prevent corruption

API_KEY="d5a8262b7cfd8f46e599b36c584bb1ec16f28436680ddaa53f700e6d8a1765fa"
PRINTER_IP="192.168.0.60"
LOGFILE="/tmp/print.log"
LAST_ID="/tmp/last_id"

# Ensure DNS
grep -q "8.8.8.8" /etc/resolv.conf || echo "nameserver 8.8.8.8" >> /etc/resolv.conf

echo "$(date '+%H:%M:%S') Ultra-fast printer started" >> "$LOGFILE"

# Keep log tiny
[ $(wc -l < "$LOGFILE" 2>/dev/null || echo 0) -gt 30 ] && tail -20 "$LOGFILE" > "$LOGFILE.tmp" && mv "$LOGFILE.tmp" "$LOGFILE"

while true; do
    # Fast API fetch
    R=$(curl -s -m 5 -k -H "Authorization: Bearer $API_KEY" "https://friendlypos.vercel.app/api/print-queue" 2>/dev/null)
    
    if [ ! -z "$R" ] && echo "$R" | grep -q '"printData"'; then
        # Get ID
        ID=$(echo "$R" | sed -n 's/.*"id":"\([^"]*\)".*/\1/p')
        [ -z "$ID" ] && ID="$(date +%s%N)"
        
        # Skip if duplicate
        [ -f "$LAST_ID" ] && [ "$ID" = "$(cat $LAST_ID)" ] && { sleep 1; continue; }
        
        # Get data
        DATA=$(echo "$R" | sed -n 's/.*"printData":"\([^"]*\)".*/\1/p')
        
        if [ ! -z "$DATA" ]; then
            echo "$(date '+%H:%M:%S') Print $ID" >> "$LOGFILE"
            
            # Direct print - no reset, minimal delay
            echo "$DATA" | base64 -d | nc -n -w 3 "$PRINTER_IP" 9100
            
            # CRITICAL: 1 second delay minimum to prevent overlap
            # This is the absolute minimum that prevents corruption
            sleep 1
            
            echo "$ID" > "$LAST_ID"
        fi
    fi
    
    # Fast poll
    sleep 1
done