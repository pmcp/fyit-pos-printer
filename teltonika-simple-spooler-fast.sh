#!/bin/sh

API_KEY="d5a8262b7cfd8f46e599b36c584bb1ec16f28436680ddaa53f700e6d8a1765fa"
PRINTER_PORT="9100"
PROCESSED="/tmp/processed_ids.txt"

# Add Google DNS if not present
grep -q "8.8.8.8" /etc/resolv.conf || echo "nameserver 8.8.8.8" >> /etc/resolv.conf

echo "$(date '+%H:%M:%S') Fast spooler started"

# Faster base64 decoder - simplified version
decode_base64() {
    awk '
    BEGIN {
        b64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
        for (i = 0; i < 64; i++) {
            b64_to_num[substr(b64, i+1, 1)] = i
        }
        b64_to_num["="] = 0
    }
    {
        gsub(/[ \t\r\n]/, "", $0)
        for (i = 1; i <= length($0); i += 4) {
            c1 = substr($0, i, 1); c2 = substr($0, i+1, 1)
            c3 = substr($0, i+2, 1); c4 = substr($0, i+3, 1)
            n1 = b64_to_num[c1]; n2 = b64_to_num[c2]
            n3 = (c3 == "=") ? 0 : b64_to_num[c3]
            n4 = (c4 == "=") ? 0 : b64_to_num[c4]
            printf "%c", (n1 * 4) + int(n2 / 16)
            if (c3 != "=") printf "%c", ((n2 % 16) * 16) + int(n3 / 4)
            if (c4 != "=") printf "%c", ((n3 % 4) * 64) + n4
        }
    }'
}

# Process jobs in parallel
process_job() {
    JOB_ID="$1"
    PRINT_DATA="$2"
    JOB_PRINTER_IP="$3"
    
    TMPFILE="/tmp/print_$JOB_ID.bin"
    
    # Decode print data
    echo "$PRINT_DATA" | decode_base64 > "$TMPFILE"
    
    if [ -s "$TMPFILE" ]; then
        # Send to printer (simplified - no reset command for speed)
        timeout 5 nc $JOB_PRINTER_IP $PRINTER_PORT < "$TMPFILE" 2>/dev/null
        
        if [ $? -eq 0 ]; then
            echo "$(date '+%H:%M:%S') Job $JOB_ID sent to $JOB_PRINTER_IP"
            echo "$JOB_ID" >> "$PROCESSED"
            
            # Mark as completed (in background)
            curl -s -m 3 -k -X POST \
                -H "x-api-key: $API_KEY" \
                -H "Content-Type: application/json" \
                -d "{\"id\":\"$JOB_ID\"}" \
                https://friendlypos.vercel.app/api/print-queue/complete >/dev/null 2>&1 &
        else
            echo "$(date '+%H:%M:%S') Job $JOB_ID failed"
        fi
    fi
    
    rm -f "$TMPFILE"
}

while true; do
    # Poll API with shorter timeout
    RESPONSE=$(curl -s -m 3 -k -H "x-api-key: $API_KEY" https://friendlypos.vercel.app/api/print-queue 2>/dev/null)
    
    if [ $? -eq 0 ] && [ ! -z "$RESPONSE" ] && echo "$RESPONSE" | grep -q '"print_data"'; then
        # Extract all job data in one pass
        JOBLIST="/tmp/jobs_$$.txt"
        echo "$RESPONSE" | grep -o '"id":"[^"]*"' | sed 's/"id":"\([^"]*\)"/\1/g' > "$JOBLIST"
        
        # Process jobs in parallel (up to 3 at once)
        ACTIVE_JOBS=0
        while IFS= read -r JOB_ID; do
            if [ ! -z "$JOB_ID" ]; then
                # Check if already processed
                if [ -f "$PROCESSED" ] && grep -q "^$JOB_ID$" "$PROCESSED"; then
                    continue
                fi
                
                # Extract job data
                PRINT_DATA=$(echo "$RESPONSE" | sed -n "s/.*\"id\":\"$JOB_ID\"[^}]*\"print_data\":\"\([^\"]*\)\".*/\1/p")
                JOB_PRINTER_IP=$(echo "$RESPONSE" | sed -n "s/.*\"id\":\"$JOB_ID\"[^}]*\"printer_ip\":\"\([^\"]*\)\".*/\1/p")
                
                if [ ! -z "$PRINT_DATA" ] && [ ! -z "$JOB_PRINTER_IP" ]; then
                    echo "$(date '+%H:%M:%S') Processing job $JOB_ID to $JOB_PRINTER_IP"
                    
                    # Run job in background
                    process_job "$JOB_ID" "$PRINT_DATA" "$JOB_PRINTER_IP" &
                    
                    ACTIVE_JOBS=$((ACTIVE_JOBS + 1))
                    
                    # Limit concurrent jobs to avoid overwhelming
                    if [ $ACTIVE_JOBS -ge 3 ]; then
                        wait  # Wait for some jobs to complete
                        ACTIVE_JOBS=0
                    fi
                fi
            fi
        done < "$JOBLIST"
        
        # Wait for remaining jobs
        wait
        rm -f "$JOBLIST"
        
        # Short sleep when jobs found
        sleep 1
    else
        # Longer sleep when no jobs
        sleep 2
    fi
done