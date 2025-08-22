#!/bin/sh

# Optimized print server with minimal delays
# Adjusts timing based on job size and printer response

API_KEY="d5a8262b7cfd8f46e599b36c584bb1ec16f28436680ddaa53f700e6d8a1765fa"
PRINTER_IP="192.168.0.60"
LOGFILE="/tmp/printserver.log"
LOCKFILE="/tmp/print.lock"
LAST_JOB_ID="/tmp/last_job_id.txt"

# Timing configuration (in seconds)
MIN_DELAY_BETWEEN_JOBS=1.5   # Minimum delay (small receipts)
MAX_DELAY_BETWEEN_JOBS=4     # Maximum delay (large receipts)
PRINTER_RESET_DELAY=0.3       # After sending reset command
BASE_PROCESSING_TIME=0.8      # Base time for printer to process

# Keep log small
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

echo "$(date '+%H:%M:%S') Fast queue print server started" >> "$LOGFILE"

# Calculate delay based on data size
calculate_delay() {
    local data_size=$1
    local delay
    
    # Estimate: ~100 bytes per line, ~50ms per line to print
    # Small receipt (<1KB): 1.5 sec
    # Medium receipt (1-3KB): 2.5 sec  
    # Large receipt (>3KB): 4 sec
    
    if [ $data_size -lt 1000 ]; then
        delay="1.5"
    elif [ $data_size -lt 3000 ]; then
        delay="2.5"
    else
        delay="4"
    fi
    
    echo "$delay"
}

# Check if printer is responding
check_printer() {
    # Send status request (DLE EOT)
    printf "\x10\x04" | nc -n -w 1 "$PRINTER_IP" 9100 2>/dev/null
    return $?
}

# Lock with timeout
acquire_lock() {
    local timeout=0
    while [ -f "$LOCKFILE" ] && [ $timeout -lt 20 ]; do
        # Check if lock owner still exists
        if [ -f "$LOCKFILE" ]; then
            pid=$(cat "$LOCKFILE" 2>/dev/null)
            if [ ! -z "$pid" ] && ! kill -0 "$pid" 2>/dev/null; then
                rm -f "$LOCKFILE"
                break
            fi
        fi
        sleep 0.2
        timeout=$((timeout + 1))
    done
    echo $$ > "$LOCKFILE"
}

release_lock() {
    rm -f "$LOCKFILE"
}

# Optimized print function
print_job() {
    local data="$1"
    local job_id="$2"
    local data_size=${#data}
    
    echo "$(date '+%H:%M:%S') Job $job_id (${data_size} bytes)" >> "$LOGFILE"
    
    # Calculate optimal delay for this job
    local delay=$(calculate_delay $data_size)
    
    # Acquire lock
    acquire_lock
    
    # Quick printer check
    if ! check_printer; then
        echo "$(date '+%H:%M:%S') Printer not responding, waiting..." >> "$LOGFILE"
        sleep 2
    fi
    
    # Reset printer (only if needed)
    printf "\x1b\x40" | nc -n -w 1 "$PRINTER_IP" 9100 2>/dev/null
    
    # Small delay after reset
    sleep 0.3
    
    # Send print data
    echo "$data" | base64 -d | nc -n -w 10 "$PRINTER_IP" 9100
    local result=$?
    
    # Dynamic delay based on job size
    sleep "$delay"
    
    # Release lock
    release_lock
    
    if [ $result -eq 0 ]; then
        echo "$(date '+%H:%M:%S') Sent OK (${delay}s delay)" >> "$LOGFILE"
        echo "$job_id" > "$LAST_JOB_ID"
    else
        echo "$(date '+%H:%M:%S') Failed" >> "$LOGFILE"
    fi
    
    trim_log
    return $result
}

# Main loop
last_print_time=0

while true; do
    # Check lock
    if [ -f "$LOCKFILE" ]; then
        pid=$(cat "$LOCKFILE" 2>/dev/null)
        if [ ! -z "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            # Another job printing
            sleep 0.5
            continue
        else
            # Stale lock
            rm -f "$LOCKFILE"
        fi
    fi
    
    # Fetch from API
    RESPONSE=$(curl -s -m 10 -k \
        -H "Authorization: Bearer $API_KEY" \
        "https://friendlypos.vercel.app/api/print-queue" 2>/dev/null)
    
    if [ $? -eq 0 ] && [ ! -z "$RESPONSE" ]; then
        if echo "$RESPONSE" | grep -q '"printData"'; then
            
            # Extract job ID
            JOB_ID=$(echo "$RESPONSE" | sed -n 's/.*"id":"\([^"]*\)".*/\1/p')
            if [ -z "$JOB_ID" ]; then
                JOB_ID="$(date +%s)"
            fi
            
            # Check duplicate
            if [ -f "$LAST_JOB_ID" ]; then
                LAST_ID=$(cat "$LAST_JOB_ID")
                if [ "$JOB_ID" = "$LAST_ID" ]; then
                    sleep 1
                    continue
                fi
            fi
            
            # Extract print data
            PRINT_DATA=$(echo "$RESPONSE" | sed -n 's/.*"printData":"\([^"]*\)".*/\1/p')
            
            if [ ! -z "$PRINT_DATA" ]; then
                # Ensure minimum time since last print
                current_time=$(date +%s)
                time_since_last=$((current_time - last_print_time))
                
                if [ $time_since_last -lt 1 ]; then
                    # Too soon, wait a bit
                    sleep 1
                fi
                
                # Process job
                print_job "$PRINT_DATA" "$JOB_ID"
                last_print_time=$(date +%s)
            fi
        fi
    fi
    
    sleep 1
done