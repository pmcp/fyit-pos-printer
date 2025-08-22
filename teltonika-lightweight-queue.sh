#!/bin/sh

# Lightweight print server optimized for Teltonika's limited resources
# Uses minimal memory and disk space

API_KEY="d5a8262b7cfd8f46e599b36c584bb1ec16f28436680ddaa53f700e6d8a1765fa"
PRINTER_IP="192.168.0.60"
LOGFILE="/tmp/printserver.log"
LOCKFILE="/tmp/print.lock"
CURRENT_JOB="/tmp/current_print.job"
LAST_JOB_ID="/tmp/last_job_id.txt"

# Keep only last 50 log lines to save space
trim_log() {
    if [ -f "$LOGFILE" ] && [ $(wc -l < "$LOGFILE") -gt 50 ]; then
        tail -30 "$LOGFILE" > "$LOGFILE.tmp"
        mv "$LOGFILE.tmp" "$LOGFILE"
    fi
}

# Ensure DNS
if ! grep -q "8.8.8.8" /etc/resolv.conf; then
    echo "nameserver 8.8.8.8" >> /etc/resolv.conf
fi

echo "$(date '+%H:%M:%S') Starting lightweight print server" >> "$LOGFILE"

# Simple lock mechanism
wait_for_printer() {
    local wait=0
    while [ -f "$LOCKFILE" ] && [ $wait -lt 30 ]; do
        sleep 1
        wait=$((wait + 1))
    done
    # Create lock
    echo $$ > "$LOCKFILE"
}

unlock_printer() {
    rm -f "$LOCKFILE"
}

# Process print job with delays to prevent corruption
print_job() {
    local data="$1"
    local job_id="$2"
    
    echo "$(date '+%H:%M:%S') Printing job $job_id" >> "$LOGFILE"
    
    # Wait for printer availability
    wait_for_printer
    
    # Reset printer buffer
    printf "\x1b\x40" | nc -n -w 1 "$PRINTER_IP" 9100 2>/dev/null
    sleep 1
    
    # Send data
    echo "$data" | base64 -d | nc -n -w 10 "$PRINTER_IP" 9100
    local result=$?
    
    # CRITICAL: Wait for printer to fully process
    sleep 4
    
    # Unlock
    unlock_printer
    
    if [ $result -eq 0 ]; then
        echo "$(date '+%H:%M:%S') Job $job_id sent OK" >> "$LOGFILE"
        # Save job ID to prevent re-printing
        echo "$job_id" > "$LAST_JOB_ID"
    else
        echo "$(date '+%H:%M:%S') Job $job_id failed" >> "$LOGFILE"
    fi
    
    trim_log
    return $result
}

# Main loop - single job at a time to save memory
while true; do
    # Check if another print is in progress
    if [ -f "$LOCKFILE" ]; then
        pid=$(cat "$LOCKFILE")
        if ! kill -0 "$pid" 2>/dev/null; then
            # Stale lock
            rm -f "$LOCKFILE"
        else
            # Another job printing, wait
            sleep 2
            continue
        fi
    fi
    
    # Fetch from API
    RESPONSE=$(curl -s -m 10 -k \
        -H "Authorization: Bearer $API_KEY" \
        "https://friendlypos.vercel.app/api/print-queue" 2>/dev/null)
    
    if [ $? -eq 0 ] && [ ! -z "$RESPONSE" ]; then
        # Check for print data
        if echo "$RESPONSE" | grep -q '"printData"'; then
            
            # Extract job ID
            JOB_ID=$(echo "$RESPONSE" | sed -n 's/.*"id":"\([^"]*\)".*/\1/p')
            if [ -z "$JOB_ID" ]; then
                JOB_ID="$(date +%s)"
            fi
            
            # Check if this job was just printed
            if [ -f "$LAST_JOB_ID" ]; then
                LAST_ID=$(cat "$LAST_JOB_ID")
                if [ "$JOB_ID" = "$LAST_ID" ]; then
                    # Skip duplicate
                    sleep 2
                    continue
                fi
            fi
            
            # Extract print data
            PRINT_DATA=$(echo "$RESPONSE" | sed -n 's/.*"printData":"\([^"]*\)".*/\1/p')
            
            if [ ! -z "$PRINT_DATA" ]; then
                # Process immediately - no queue to save memory
                print_job "$PRINT_DATA" "$JOB_ID"
                
                # IMPORTANT: Extra delay after successful print
                # This prevents next job from corrupting
                sleep 3
            fi
        fi
    fi
    
    # Poll interval
    sleep 2
done