#!/bin/sh

API_KEY="d5a8262b7cfd8f46e599b36c584bb1ec16f28436680ddaa53f700e6d8a1765fa"
PRINTER_IP="192.168.0.60"
PRINTER_PORT="9100"
LOGFILE="/tmp/spooler.log"
PROCESSED="/tmp/processed_ids.txt"

# Add Google DNS if not present
grep -q "8.8.8.8" /etc/resolv.conf || echo "nameserver 8.8.8.8" >> /etc/resolv.conf

echo "$(date '+%H:%M:%S') Simple spooler started"

# BusyBox-compatible base64 decoder using awk
decode_base64() {
    awk '
    BEGIN {
        # Base64 character set
        b64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
        
        # Create reverse lookup
        for (i = 0; i < 64; i++) {
            c = substr(b64, i+1, 1)
            b64_to_num[c] = i
        }
        b64_to_num["="] = 0
    }
    
    {
        # Remove whitespace
        gsub(/[ \t\r\n]/, "", $0)
        
        # Process in groups of 4 characters
        for (i = 1; i <= length($0); i += 4) {
            # Get 4 characters
            c1 = substr($0, i, 1)
            c2 = substr($0, i+1, 1)
            c3 = substr($0, i+2, 1)
            c4 = substr($0, i+3, 1)
            
            # Convert to numbers
            n1 = b64_to_num[c1]
            n2 = b64_to_num[c2]
            n3 = (c3 == "=") ? 0 : b64_to_num[c3]
            n4 = (c4 == "=") ? 0 : b64_to_num[c4]
            
            # Decode
            printf "%c", (n1 * 4) + int(n2 / 16)
            if (c3 != "=") printf "%c", ((n2 % 16) * 16) + int(n3 / 4)
            if (c4 != "=") printf "%c", ((n3 % 4) * 64) + n4
        }
    }
    '
}

while true; do
    # Poll the API
    RESPONSE=$(curl -s -m 5 -k -H "x-api-key: $API_KEY" https://friendlypos.vercel.app/api/print-queue 2>/dev/null)
    
    if [ $? -eq 0 ] && [ ! -z "$RESPONSE" ]; then
        # Check if there's actual print data
        if echo "$RESPONSE" | grep -q '"print_data"'; then
            # Save all job IDs to a temp file and process them
            JOBLIST="/tmp/jobs_$$.txt"
            echo "$RESPONSE" | grep -o '"id":"[^"]*"' | sed 's/"id":"\([^"]*\)"/\1/g' > "$JOBLIST"
            
            # Process each job ID from the file
            while IFS= read -r JOB_ID; do
                if [ ! -z "$JOB_ID" ]; then
                    # Check if already processed
                    if [ -f "$PROCESSED" ] && grep -q "^$JOB_ID$" "$PROCESSED"; then
                        echo "$(date '+%H:%M:%S') Job $JOB_ID already processed"
                    else
                        # Extract print data and printer IP for this specific job
                        PRINT_DATA=$(echo "$RESPONSE" | sed -n "s/.*\"id\":\"$JOB_ID\"[^}]*\"print_data\":\"\([^\"]*\)\".*/\1/p")
                        JOB_PRINTER_IP=$(echo "$RESPONSE" | sed -n "s/.*\"id\":\"$JOB_ID\"[^}]*\"printer_ip\":\"\([^\"]*\)\".*/\1/p")
                        
                        if [ ! -z "$PRINT_DATA" ] && [ ! -z "$JOB_PRINTER_IP" ]; then
                            echo "$(date '+%H:%M:%S') Printing job $JOB_ID to $JOB_PRINTER_IP"
                            
                            # Create a temporary file for the decoded data
                            TMPFILE="/tmp/print_$JOB_ID.bin"
                            
                            # Decode and send to printer
                            echo "$PRINT_DATA" | decode_base64 > "$TMPFILE"
                            
                            if [ -s "$TMPFILE" ]; then
                                # Try to send data to printer using multiple methods
                                SUCCESS=0
                                
                                # Method 1: Try with timeout using ( ) subshell
                                (
                                    printf '\x1b\x40'
                                    sleep 1
                                    cat "$TMPFILE"
                                ) | timeout 10 nc $JOB_PRINTER_IP $PRINTER_PORT 2>/dev/null
                                
                                if [ $? -eq 0 ]; then
                                    SUCCESS=1
                                else
                                    # Method 2: Try direct telnet approach
                                    (
                                        printf '\x1b\x40'
                                        sleep 1
                                        cat "$TMPFILE"
                                        sleep 1
                                    ) | telnet $JOB_PRINTER_IP $PRINTER_PORT 2>/dev/null 1>/dev/null &
                                    TELNET_PID=$!
                                    sleep 3
                                    kill $TELNET_PID 2>/dev/null
                                    SUCCESS=1
                                fi
                                
                                if [ $SUCCESS -eq 1 ]; then
                                    echo "$(date '+%H:%M:%S') Job $JOB_ID sent"
                                    echo "$JOB_ID" >> "$PROCESSED"
                                    
                                    # Mark as completed
                                    curl -s -m 5 -k -X POST \
                                        -H "x-api-key: $API_KEY" \
                                        -H "Content-Type: application/json" \
                                        -d "{\"id\":\"$JOB_ID\"}" \
                                        https://friendlypos.vercel.app/api/print-queue/complete 2>/dev/null
                                    
                                    sleep 2
                                else
                                    echo "$(date '+%H:%M:%S') Job $JOB_ID failed"
                                fi
                            else
                                echo "$(date '+%H:%M:%S') Failed to decode job $JOB_ID"
                            fi
                            
                            # Clean up
                            rm -f "$TMPFILE"
                        fi
                    fi
                fi
            done < "$JOBLIST"
            
            # Clean up job list
            rm -f "$JOBLIST"
        fi
    fi
    
    sleep 2
done