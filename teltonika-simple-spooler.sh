#!/bin/sh

# Simple reliable print spooler for Teltonika
API_KEY="d5a8262b7cfd8f46e599b36c584bb1ec16f28436680ddaa53f700e6d8a1765fa"
PRINTER_IP="192.168.0.60"
PRINTER_PORT="9100"
LOGFILE="/tmp/spooler.log"
PROCESSED="/tmp/processed_ids.txt"

# Ensure DNS
grep -q "8.8.8.8" /etc/resolv.conf || echo "nameserver 8.8.8.8" >> /etc/resolv.conf

echo "$(date '+%H:%M:%S') Simple spooler started" >> "$LOGFILE"

# Keep processed file small
cleanup_processed() {
    if [ -f "$PROCESSED" ] && [ $(wc -l < "$PROCESSED") -gt 100 ]; then
        tail -50 "$PROCESSED" > "$PROCESSED.tmp"
        mv "$PROCESSED.tmp" "$PROCESSED"
    fi
}

# Main loop
while true; do
    # Fetch from API
    RESPONSE=$(curl -s -m 5 -k \
        -H "x-api-key: $API_KEY" \
        "https://friendlypos.vercel.app/api/print-queue" 2>/dev/null)
    
    if [ $? -eq 0 ] && [ ! -z "$RESPONSE" ]; then
        # Check for print data
        if echo "$RESPONSE" | grep -q '"printData"'; then
            
            # Extract job ID
            JOB_ID=$(echo "$RESPONSE" | sed -n 's/.*"id":"\([^"]*\)".*/\1/p')
            [ -z "$JOB_ID" ] && JOB_ID="$(date +%s)"
            
            # Check if already processed
            if [ -f "$PROCESSED" ] && grep -q "^$JOB_ID$" "$PROCESSED"; then
                # Already done, skip
                echo "$(date '+%H:%M:%S') Skip duplicate $JOB_ID" >> "$LOGFILE"
            else
                # Extract print data
                PRINT_DATA=$(echo "$RESPONSE" | sed -n 's/.*"printData":"\([^"]*\)".*/\1/p')
                
                if [ ! -z "$PRINT_DATA" ]; then
                    echo "$(date '+%H:%M:%S') Printing job $JOB_ID" >> "$LOGFILE"
                    
                    # Reset printer
                    printf "\x1b\x40" | nc -n -w 1 "$PRINTER_IP" "$PRINTER_PORT" 2>/dev/null
                    sleep 1
                    
                    # Send to printer
                    echo "$PRINT_DATA" | base64 -d | nc -n -w 10 "$PRINTER_IP" "$PRINTER_PORT"
                    
                    if [ $? -eq 0 ]; then
                        echo "$(date '+%H:%M:%S') Job $JOB_ID printed OK" >> "$LOGFILE"
                        echo "$JOB_ID" >> "$PROCESSED"
                        cleanup_processed
                    else
                        echo "$(date '+%H:%M:%S') Job $JOB_ID failed" >> "$LOGFILE"
                    fi
                    
                    # Wait between prints to prevent corruption
                    sleep 2
                fi
            fi
        fi
    else
        echo "$(date '+%H:%M:%S') API fetch failed" >> "$LOGFILE"
    fi
    
    # Poll every 2 seconds
    sleep 2
done