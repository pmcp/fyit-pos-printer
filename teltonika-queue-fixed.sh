#!/bin/sh

# Print server with proper job queuing and locking
API_KEY="d5a8262b7cfd8f46e599b36c584bb1ec16f28436680ddaa53f700e6d8a1765fa"
PRINTER_IP="192.168.0.60"
LOGFILE="/tmp/printserver.log"
LOCKFILE="/tmp/printserver.lock"
JOBDIR="/tmp/print_jobs"
PROCESSED_FILE="/tmp/processed_jobs.txt"

# Create job directory
mkdir -p "$JOBDIR"
touch "$PROCESSED_FILE"

# Ensure DNS is configured
if ! grep -q "8.8.8.8" /etc/resolv.conf; then
    echo "nameserver 8.8.8.8" >> /etc/resolv.conf
    echo "nameserver 8.8.4.4" >> /etc/resolv.conf
fi

echo "$(date '+%Y-%m-%d %H:%M:%S') Starting queue-based print server..." >> "$LOGFILE"

# Function to acquire lock
acquire_lock() {
    local timeout=30
    local elapsed=0
    
    while [ -f "$LOCKFILE" ] && [ $elapsed -lt $timeout ]; do
        sleep 0.5
        elapsed=$((elapsed + 1))
    done
    
    if [ $elapsed -ge $timeout ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') Lock timeout, removing stale lock" >> "$LOGFILE"
        rm -f "$LOCKFILE"
    fi
    
    echo $$ > "$LOCKFILE"
}

# Function to release lock
release_lock() {
    rm -f "$LOCKFILE"
}

# Function to process a single job
process_job() {
    local job_file=$1
    local job_id=$(basename "$job_file" .job)
    
    echo "$(date '+%Y-%m-%d %H:%M:%S') Processing job $job_id" >> "$LOGFILE"
    
    # Read the base64 data from job file
    PRINT_DATA=$(cat "$job_file")
    
    if [ ! -z "$PRINT_DATA" ]; then
        # Acquire lock before sending to printer
        acquire_lock
        
        # Send to printer with proper timing
        echo "$PRINT_DATA" | base64 -d | nc -n -w 5 "$PRINTER_IP" 9100
        RESULT=$?
        
        # Wait for printer to process
        sleep 1
        
        # Release lock
        release_lock
        
        if [ $RESULT -eq 0 ]; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') Job $job_id printed successfully" >> "$LOGFILE"
            # Mark as processed
            echo "$job_id" >> "$PROCESSED_FILE"
            # Remove job file
            rm -f "$job_file"
        else
            echo "$(date '+%Y-%m-%d %H:%M:%S') Job $job_id failed to print" >> "$LOGFILE"
            # Move to failed directory for retry
            mkdir -p "$JOBDIR/failed"
            mv "$job_file" "$JOBDIR/failed/"
        fi
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') Job $job_id is empty" >> "$LOGFILE"
        rm -f "$job_file"
    fi
}

# Main loop
while true; do
    # Fetch from API
    RESPONSE=$(curl -s -m 10 -k \
        -H "Authorization: Bearer $API_KEY" \
        "https://friendlypos.vercel.app/api/print-queue" 2>/dev/null)
    
    if [ $? -eq 0 ] && [ ! -z "$RESPONSE" ]; then
        # Check if response contains print data
        if echo "$RESPONSE" | grep -q '"printData"'; then
            
            # Extract job ID if available, otherwise use timestamp
            JOB_ID=$(echo "$RESPONSE" | sed -n 's/.*"id":"\([^"]*\)".*/\1/p')
            if [ -z "$JOB_ID" ]; then
                JOB_ID="job_$(date +%s)_$$"
            fi
            
            # Check if already processed
            if grep -q "^$JOB_ID$" "$PROCESSED_FILE" 2>/dev/null; then
                echo "$(date '+%Y-%m-%d %H:%M:%S') Job $JOB_ID already processed, skipping" >> "$LOGFILE"
            else
                # Extract base64 data
                PRINT_DATA=$(echo "$RESPONSE" | sed -n 's/.*"printData":"\([^"]*\)".*/\1/p')
                
                if [ ! -z "$PRINT_DATA" ]; then
                    # Save to job queue
                    JOB_FILE="$JOBDIR/$JOB_ID.job"
                    echo "$PRINT_DATA" > "$JOB_FILE"
                    echo "$(date '+%Y-%m-%d %H:%M:%S') Queued job $JOB_ID" >> "$LOGFILE"
                fi
            fi
        fi
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') API fetch failed" >> "$LOGFILE"
    fi
    
    # Process any pending jobs in order
    for job_file in "$JOBDIR"/*.job 2>/dev/null; do
        if [ -f "$job_file" ]; then
            process_job "$job_file"
            # Add delay between jobs to prevent overlap
            sleep 2
        fi
    done
    
    # Retry failed jobs every 10 iterations
    if [ $(($(date +%s) % 20)) -eq 0 ]; then
        for job_file in "$JOBDIR/failed"/*.job 2>/dev/null; do
            if [ -f "$job_file" ]; then
                echo "$(date '+%Y-%m-%d %H:%M:%S') Retrying failed job..." >> "$LOGFILE"
                mv "$job_file" "$JOBDIR/"
            fi
        done
    fi
    
    # Clean old processed jobs list (keep last 100)
    if [ $(wc -l < "$PROCESSED_FILE" 2>/dev/null || echo 0) -gt 100 ]; then
        tail -50 "$PROCESSED_FILE" > "$PROCESSED_FILE.tmp"
        mv "$PROCESSED_FILE.tmp" "$PROCESSED_FILE"
    fi
    
    sleep 2
done