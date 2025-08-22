#!/bin/sh

# Enhanced print server with unlimited job queue capacity
API_KEY="d5a8262b7cfd8f46e599b36c584bb1ec16f28436680ddaa53f700e6d8a1765fa"
PRINTER_IP="192.168.0.60"
LOGFILE="/tmp/printserver.log"
LOCKFILE="/tmp/printserver.lock"
JOBDIR="/tmp/print_jobs"
PROCESSED_FILE="/tmp/processed_jobs.txt"
QUEUE_STATUS="/tmp/queue_status.txt"

# Configurable delays (in seconds)
DELAY_BETWEEN_JOBS=3      # Time between print jobs (increase if gibberish)
DELAY_AFTER_PRINT=2       # Wait after sending to printer
API_POLL_INTERVAL=2       # How often to check API

# Create necessary directories and files
mkdir -p "$JOBDIR"
mkdir -p "$JOBDIR/pending"
mkdir -p "$JOBDIR/processing"
mkdir -p "$JOBDIR/failed"
mkdir -p "$JOBDIR/completed"
touch "$PROCESSED_FILE"

# Ensure DNS is configured
if ! grep -q "8.8.8.8" /etc/resolv.conf; then
    echo "nameserver 8.8.8.8" >> /etc/resolv.conf
    echo "nameserver 8.8.4.4" >> /etc/resolv.conf
fi

echo "$(date '+%Y-%m-%d %H:%M:%S') Starting enhanced queue print server..." >> "$LOGFILE"
echo "$(date '+%Y-%m-%d %H:%M:%S') Delay between jobs: ${DELAY_BETWEEN_JOBS}s" >> "$LOGFILE"

# Function to update queue status
update_queue_status() {
    local pending=$(ls -1 "$JOBDIR/pending" 2>/dev/null | wc -l)
    local processing=$(ls -1 "$JOBDIR/processing" 2>/dev/null | wc -l)
    local failed=$(ls -1 "$JOBDIR/failed" 2>/dev/null | wc -l)
    
    echo "Queue Status [$(date '+%H:%M:%S')]" > "$QUEUE_STATUS"
    echo "Pending: $pending" >> "$QUEUE_STATUS"
    echo "Processing: $processing" >> "$QUEUE_STATUS"
    echo "Failed: $failed" >> "$QUEUE_STATUS"
    
    if [ $pending -gt 10 ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') WARNING: Queue backlog - $pending jobs pending" >> "$LOGFILE"
    fi
}

# Function to acquire lock with timeout
acquire_lock() {
    local timeout=60
    local elapsed=0
    
    while [ -f "$LOCKFILE" ] && [ $elapsed -lt $timeout ]; do
        sleep 0.2
        elapsed=$((elapsed + 1))
    done
    
    if [ $elapsed -ge $timeout ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: Lock timeout, forcing unlock" >> "$LOGFILE"
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
    local job_name=$(basename "$job_file")
    local job_id="${job_name%.job}"
    
    # Move to processing
    mv "$job_file" "$JOBDIR/processing/$job_name"
    
    echo "$(date '+%Y-%m-%d %H:%M:%S') Processing job $job_id" >> "$LOGFILE"
    
    # Read the base64 data
    PRINT_DATA=$(cat "$JOBDIR/processing/$job_name")
    
    if [ ! -z "$PRINT_DATA" ]; then
        # Acquire lock for printer access
        acquire_lock
        
        # Clear printer buffer first (send reset)
        printf "\x1b\x40" | nc -n -w 1 "$PRINTER_IP" 9100 2>/dev/null
        sleep 0.5
        
        # Send print data
        echo "$PRINT_DATA" | base64 -d | nc -n -w 10 "$PRINTER_IP" 9100
        RESULT=$?
        
        # Wait for printer to finish
        sleep "$DELAY_AFTER_PRINT"
        
        # Release lock
        release_lock
        
        if [ $RESULT -eq 0 ]; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') Job $job_id completed successfully" >> "$LOGFILE"
            # Mark as processed
            echo "$job_id|$(date +%s)" >> "$PROCESSED_FILE"
            # Move to completed
            mv "$JOBDIR/processing/$job_name" "$JOBDIR/completed/"
            
            # Clean old completed jobs (keep last 20)
            COMPLETED_COUNT=$(ls -1 "$JOBDIR/completed" | wc -l)
            if [ $COMPLETED_COUNT -gt 20 ]; then
                ls -1t "$JOBDIR/completed" | tail -n +21 | while read old_job; do
                    rm -f "$JOBDIR/completed/$old_job"
                done
            fi
        else
            echo "$(date '+%Y-%m-%d %H:%M:%S') Job $job_id failed (error $RESULT)" >> "$LOGFILE"
            # Move to failed for retry
            mv "$JOBDIR/processing/$job_name" "$JOBDIR/failed/"
        fi
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') Job $job_id is empty, removing" >> "$LOGFILE"
        rm -f "$JOBDIR/processing/$job_name"
    fi
    
    # Update status
    update_queue_status
}

# Function to fetch new jobs from API
fetch_jobs() {
    RESPONSE=$(curl -s -m 10 -k \
        -H "Authorization: Bearer $API_KEY" \
        "https://friendlypos.vercel.app/api/print-queue" 2>/dev/null)
    
    if [ $? -eq 0 ] && [ ! -z "$RESPONSE" ]; then
        # Check if response contains print data
        if echo "$RESPONSE" | grep -q '"printData"'; then
            
            # Extract job ID or generate one
            JOB_ID=$(echo "$RESPONSE" | sed -n 's/.*"id":"\([^"]*\)".*/\1/p')
            if [ -z "$JOB_ID" ]; then
                JOB_ID="job_$(date +%s%N)_$$"
            fi
            
            # Check if already processed recently (within last hour)
            RECENT_CUTOFF=$(($(date +%s) - 3600))
            if grep "^$JOB_ID|" "$PROCESSED_FILE" 2>/dev/null | while IFS='|' read id timestamp; do
                [ "$timestamp" -gt "$RECENT_CUTOFF" ] && exit 0 || exit 1
            done; then
                echo "$(date '+%Y-%m-%d %H:%M:%S') Job $JOB_ID already processed recently" >> "$LOGFILE"
            else
                # Extract base64 data
                PRINT_DATA=$(echo "$RESPONSE" | sed -n 's/.*"printData":"\([^"]*\)".*/\1/p')
                
                if [ ! -z "$PRINT_DATA" ]; then
                    # Save to pending queue
                    JOB_FILE="$JOBDIR/pending/${JOB_ID}.job"
                    echo "$PRINT_DATA" > "$JOB_FILE"
                    echo "$(date '+%Y-%m-%d %H:%M:%S') Queued new job $JOB_ID" >> "$LOGFILE"
                    update_queue_status
                fi
            fi
        fi
    fi
}

# Background job processor
process_queue() {
    while true; do
        # Process pending jobs in order (oldest first)
        for job_file in $(ls -1tr "$JOBDIR/pending"/*.job 2>/dev/null | head -1); do
            if [ -f "$job_file" ]; then
                process_job "$job_file"
                # Delay between jobs to prevent printer overload
                sleep "$DELAY_BETWEEN_JOBS"
            fi
        done
        
        # Retry failed jobs every 30 seconds
        if [ $(($(date +%s) % 30)) -eq 0 ]; then
            for job_file in "$JOBDIR/failed"/*.job 2>/dev/null; do
                if [ -f "$job_file" ]; then
                    echo "$(date '+%Y-%m-%d %H:%M:%S') Retrying failed job..." >> "$LOGFILE"
                    mv "$job_file" "$JOBDIR/pending/"
                fi
            done
        fi
        
        # If no jobs, wait a bit
        if [ $(ls -1 "$JOBDIR/pending" 2>/dev/null | wc -l) -eq 0 ]; then
            sleep 1
        fi
    done
}

# Start queue processor in background
process_queue &
PROCESSOR_PID=$!
echo "$(date '+%Y-%m-%d %H:%M:%S') Queue processor started (PID: $PROCESSOR_PID)" >> "$LOGFILE"

# Main loop - fetch jobs from API
while true; do
    fetch_jobs
    
    # Clean old processed jobs list (keep last 500)
    if [ $(wc -l < "$PROCESSED_FILE" 2>/dev/null || echo 0) -gt 500 ]; then
        tail -250 "$PROCESSED_FILE" > "$PROCESSED_FILE.tmp"
        mv "$PROCESSED_FILE.tmp" "$PROCESSED_FILE"
    fi
    
    sleep "$API_POLL_INTERVAL"
done