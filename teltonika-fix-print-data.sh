#!/bin/sh
# Teltonika Print Server - Fixes print_data for TM-m30
# Removes problematic ESC/POS commands while keeping formatting

API_URL="https://friendlypos.vercel.app/api/print-queue"
API_KEY="d5a8262b7cfd8f46e599b36c584bb1ec16f28436680ddaa53f700e6d8a1765fa"
POLL_INTERVAL=2
LOG_FILE="/tmp/printserver.log"

exec >> "$LOG_FILE" 2>&1
echo "$(date) - Print Server Started (Fix Print Data Version)"

# Function to decode base64
decode_base64() {
    if command -v base64 >/dev/null 2>&1; then
        base64 -d 2>/dev/null || base64
    else
        awk '
        BEGIN {
            b64="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
        }
        {
            gsub(/=/, "")
            for(i=1; i<=length($0); i+=4) {
                s = substr($0, i, 4)
                n = 0
                for(j=1; j<=length(s); j++) {
                    c = substr(s, j, 1)
                    p = index(b64, c) - 1
                    n = n * 64 + p
                }
                for(j=3; j>=1; j--) {
                    if(length(s) > j) {
                        printf "%c", n % 256
                        n = int(n / 256)
                    }
                }
            }
        }'
    fi
}

# Function to mark order as complete
mark_complete() {
    local order_id=$1
    curl -s -X POST -H "X-API-Key: $API_KEY" \
        "https://friendlypos.vercel.app/api/print-queue/$order_id/complete" >/dev/null 2>&1
    echo "$(date) - Order $order_id marked as complete"
}

# Function to mark order as failed
mark_failed() {
    local order_id=$1
    local error_msg=$2
    curl -s -X POST -H "X-API-Key: $API_KEY" \
        -H "Content-Type: application/json" \
        -d "{\"error\":\"$error_msg\"}" \
        "https://friendlypos.vercel.app/api/print-queue/$order_id/fail" >/dev/null 2>&1
    echo "$(date) - Order $order_id marked as failed: $error_msg"
}

# Main loop
while true; do
    RESPONSE=$(curl -s -H "X-API-Key: $API_KEY" "$API_URL" 2>&1)
    
    if [ $? -ne 0 ]; then
        echo "$(date) - ERROR: Failed to fetch orders from API"
        sleep $POLL_INTERVAL
        continue
    fi
    
    if [ ! -z "$RESPONSE" ] && [ "$RESPONSE" != "[]" ] && [ "$RESPONSE" != "null" ]; then
        echo "$(date) - Orders found"
        
        ORDERS=$(echo "$RESPONSE" | sed 's/^\[//; s/\]$//' | sed 's/},{/}\n{/g')
        
        echo "$ORDERS" | while IFS= read -r ORDER; do
            [ -z "$ORDER" ] && continue
            
            # Extract order ID
            ID=$(echo "$ORDER" | sed -n 's/.*"id":"\([^"]*\)".*/\1/p')
            [ -z "$ID" ] && ID=$(echo "$ORDER" | sed -n 's/.*"queue_id":\([0-9]*\).*/\1/p')
            
            if [ -z "$ID" ]; then
                continue
            fi
            
            # Extract printer IP
            PRINTER_IP=$(echo "$ORDER" | sed -n 's/.*"printer_ip":"\([^"]*\)".*/\1/p')
            [ -z "$PRINTER_IP" ] && PRINTER_IP=$(echo "$ORDER" | sed -n 's/.*"ip_address":"\([^"]*\)".*/\1/p')
            
            if [ -z "$PRINTER_IP" ]; then
                continue
            fi
            
            # Extract printer port
            PRINTER_PORT=$(echo "$ORDER" | sed -n 's/.*"port":\([0-9]*\).*/\1/p')
            [ -z "$PRINTER_PORT" ] && PRINTER_PORT=$(echo "$ORDER" | sed -n 's/.*"printer_port":\([0-9]*\).*/\1/p')
            [ -z "$PRINTER_PORT" ] && PRINTER_PORT="9100"
            
            echo "$(date) - Processing order $ID for printer $PRINTER_IP:$PRINTER_PORT"
            
            # Extract print_data
            PRINT_DATA=$(echo "$ORDER" | sed -n 's/.*"print_data":"\([^"]*\)".*/\1/p')
            
            if [ -z "$PRINT_DATA" ]; then
                echo "$(date) - ERROR: No print_data found for order $ID"
                mark_failed "$ID" "No print data available"
                continue
            fi
            
            echo "$(date) - Fixing print_data for TM-m30 compatibility"
            
            # Decode to temp file
            TEMP_FILE="/tmp/order_${ID}_raw.bin"
            FIXED_FILE="/tmp/order_${ID}_fixed.bin"
            
            echo "$PRINT_DATA" | decode_base64 > "$TEMP_FILE"
            
            # Fix the print data using sed to remove problematic bytes
            # This removes ESC ! commands (1B 21 XX) that cause issues
            if command -v hexdump >/dev/null 2>&1 && command -v xxd >/dev/null 2>&1; then
                # Convert to hex, remove problematic sequences, convert back
                xxd -p "$TEMP_FILE" | \
                    sed 's/1b2110/1b2108/g; s/1b2120/1b2108/g; s/1b2130/1b2108/g; s/1b6404//g' | \
                    xxd -r -p > "$FIXED_FILE"
            else
                # Fallback: just use the original
                cp "$TEMP_FILE" "$FIXED_FILE"
            fi
            
            # Send fixed data to printer
            cat "$FIXED_FILE" | nc $PRINTER_IP $PRINTER_PORT
            
            if [ $? -eq 0 ]; then
                echo "$(date) - Order $ID printed successfully"
                mark_complete "$ID"
            else
                echo "$(date) - ERROR: Failed to print order $ID"
                mark_failed "$ID" "Failed to print"
            fi
            
            # Cleanup
            rm -f "$TEMP_FILE" "$FIXED_FILE"
            
            sleep 1
        done
    fi
    
    sleep $POLL_INTERVAL
done