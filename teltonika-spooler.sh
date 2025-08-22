#!/bin/sh

# Professional print spooler for Teltonika RUT956
# Uses proper queue management like CUPS/Windows spooler

API_KEY="d5a8262b7cfd8f46e599b36c584bb1ec16f28436680ddaa53f700e6d8a1765fa"
PRINTER_IP="192.168.0.60"
PRINTER_PORT="9100"

# Spool directories
SPOOL_DIR="/tmp/spool"
SPOOL_NEW="$SPOOL_DIR/new"
SPOOL_ACTIVE="$SPOOL_DIR/active"
SPOOL_DONE="$SPOOL_DIR/done"
LOGFILE="/tmp/spooler.log"

# Create spool structure
mkdir -p "$SPOOL_NEW" "$SPOOL_ACTIVE" "$SPOOL_DONE"

# PID files for the two processes
FETCHER_PID="/var/run/print_fetcher.pid"
SPOOLER_PID="/var/run/print_spooler.pid"

# Ensure DNS
grep -q "8.8.8.8" /etc/resolv.conf || echo "nameserver 8.8.8.8" >> /etc/resolv.conf

echo "$(date '+%H:%M:%S') Print spooler starting..." >> "$LOGFILE"

# Function 1: Fetcher - Gets jobs from API and queues them
start_fetcher() {
    echo $$ > "$FETCHER_PID"
    echo "$(date '+%H:%M:%S') Fetcher started (PID $$)" >> "$LOGFILE"
    
    while true; do
        # Fetch from API
        R=$(curl -s -m 5 -k -H "Authorization: Bearer $API_KEY" "https://friendlypos.vercel.app/api/print-queue" 2>/dev/null)
        
        if [ ! -z "$R" ] && echo "$R" | grep -q '"printData"'; then
            # Extract ID
            ID=$(echo "$R" | sed -n 's/.*"id":"\([^"]*\)".*/\1/p')
            [ -z "$ID" ] && ID="$(date +%s%N)"
            
            # Check if already spooled
            if ! ls $SPOOL_NEW/$ID.* $SPOOL_ACTIVE/$ID.* $SPOOL_DONE/$ID.* >/dev/null 2>&1; then
                # Extract data
                DATA=$(echo "$R" | sed -n 's/.*"printData":"\([^"]*\)".*/\1/p')
                
                if [ ! -z "$DATA" ]; then
                    # Spool the job with timestamp for ordering
                    TIMESTAMP=$(date +%s%N)
                    SPOOL_FILE="$SPOOL_NEW/${ID}.${TIMESTAMP}.job"
                    echo "$DATA" > "$SPOOL_FILE"
                    echo "$(date '+%H:%M:%S') Spooled job $ID" >> "$LOGFILE"
                fi
            fi
        fi
        
        # Clean old done jobs (keep last 20)
        ls -t1 "$SPOOL_DONE" 2>/dev/null | tail -n +21 | while read f; do
            rm -f "$SPOOL_DONE/$f"
        done
        
        sleep 1
    done
}

# Function 2: Spooler - Processes queued jobs sequentially
start_spooler() {
    echo $$ > "$SPOOLER_PID"
    echo "$(date '+%H:%M:%S') Spooler started (PID $$)" >> "$LOGFILE"
    
    while true; do
        # Get oldest job from queue (FIFO)
        JOB=$(ls -1 "$SPOOL_NEW" 2>/dev/null | sort | head -1)
        
        if [ ! -z "$JOB" ]; then
            # Move to active
            mv "$SPOOL_NEW/$JOB" "$SPOOL_ACTIVE/$JOB"
            
            # Extract job ID for logging
            JOB_ID=$(echo "$JOB" | cut -d'.' -f1)
            
            echo "$(date '+%H:%M:%S') Printing job $JOB_ID" >> "$LOGFILE"
            
            # Read print data
            DATA=$(cat "$SPOOL_ACTIVE/$JOB")
            
            # Send to printer with proper handling
            if [ ! -z "$DATA" ]; then
                # Clear any printer errors first
                printf "\x1b\x40" | nc -n -w 1 "$PRINTER_IP" "$PRINTER_PORT" 2>/dev/null
                sleep 1
                
                # Send print data
                echo "$DATA" | base64 -d | nc -n -w 10 "$PRINTER_IP" "$PRINTER_PORT"
                RESULT=$?
                
                if [ $RESULT -eq 0 ]; then
                    echo "$(date '+%H:%M:%S') Job $JOB_ID completed" >> "$LOGFILE"
                    mv "$SPOOL_ACTIVE/$JOB" "$SPOOL_DONE/$JOB"
                    
                    # Critical: Wait for printer to finish processing
                    # This prevents corruption when multiple jobs arrive
                    sleep 1
                else
                    echo "$(date '+%H:%M:%S') Job $JOB_ID failed, requeueing" >> "$LOGFILE"
                    mv "$SPOOL_ACTIVE/$JOB" "$SPOOL_NEW/$JOB"
                    sleep 2
                fi
            else
                # Empty job, discard
                rm -f "$SPOOL_ACTIVE/$JOB"
            fi
        else
            # No jobs, wait
            sleep 1
        fi
    done
}

# Stop function
stop_all() {
    echo "$(date '+%H:%M:%S') Stopping spooler..." >> "$LOGFILE"
    
    [ -f "$FETCHER_PID" ] && kill $(cat "$FETCHER_PID") 2>/dev/null && rm -f "$FETCHER_PID"
    [ -f "$SPOOLER_PID" ] && kill $(cat "$SPOOLER_PID") 2>/dev/null && rm -f "$SPOOLER_PID"
    
    # Kill any orphaned processes
    killall teltonika-spooler.sh 2>/dev/null
}

# Main script logic
case "${1:-start}" in
    start)
        # Stop any existing instances
        stop_all
        
        # Start fetcher in background
        (start_fetcher) &
        
        # Start spooler in background
        (start_spooler) &
        
        echo "Print spooler started"
        echo "Monitor with: tail -f $LOGFILE"
        echo "Check queue: ls -la $SPOOL_NEW"
        ;;
        
    stop)
        stop_all
        echo "Print spooler stopped"
        ;;
        
    status)
        echo "=== Spooler Status ==="
        echo "New jobs: $(ls -1 $SPOOL_NEW 2>/dev/null | wc -l)"
        echo "Active: $(ls -1 $SPOOL_ACTIVE 2>/dev/null | wc -l)"
        echo "Completed: $(ls -1 $SPOOL_DONE 2>/dev/null | wc -l)"
        
        if [ -f "$FETCHER_PID" ] && kill -0 $(cat "$FETCHER_PID") 2>/dev/null; then
            echo "Fetcher: Running (PID $(cat $FETCHER_PID))"
        else
            echo "Fetcher: Stopped"
        fi
        
        if [ -f "$SPOOLER_PID" ] && kill -0 $(cat "$SPOOLER_PID") 2>/dev/null; then
            echo "Spooler: Running (PID $(cat $SPOOLER_PID))"
        else
            echo "Spooler: Stopped"
        fi
        ;;
        
    restart)
        stop_all
        sleep 1
        (start_fetcher) &
        (start_spooler) &
        echo "Print spooler restarted"
        ;;
        
    *)
        echo "Usage: $0 {start|stop|status|restart}"
        exit 1
        ;;
esac