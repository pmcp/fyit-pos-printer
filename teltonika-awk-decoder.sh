#!/bin/sh
# Teltonika Print Server - AWK Base64 Decoder Version
# This version uses pure awk for Base64 decoding since base64 command is missing

API_URL="https://friendlypos.vercel.app/api/print-queue"
API_KEY="d5a8262b7cfd8f46e599b36c584bb1ec16f28436680ddaa53f700e6d8a1765fa"
POLL_INTERVAL=2
LOG_FILE="/tmp/printserver.log"

# Redirect output to log file
exec >> "$LOG_FILE" 2>&1
echo "$(date) - Print Server Started (AWK Decoder Version)"

# Function to decode base64 using awk
decode_base64_awk() {
    awk '
    BEGIN {
        # Base64 alphabet
        b64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
        
        # Build reverse lookup
        for(i=0; i<64; i++) {
            c = substr(b64, i+1, 1)
            b64_val[c] = i
        }
    }
    {
        # Remove padding
        gsub(/=/, "")
        
        # Process in groups of 4 characters
        len = length($0)
        for(i=1; i<=len; i+=4) {
            # Get 4 characters
            c1 = substr($0, i, 1)
            c2 = substr($0, i+1, 1) 
            c3 = substr($0, i+2, 1)
            c4 = substr($0, i+3, 1)
            
            # Convert to values
            v1 = (c1 in b64_val) ? b64_val[c1] : 0
            v2 = (c2 in b64_val) ? b64_val[c2] : 0
            v3 = (c3 in b64_val) ? b64_val[c3] : 0
            v4 = (c4 in b64_val) ? b64_val[c4] : 0
            
            # Decode to 3 bytes
            if(i+0 <= len) printf "%c", v1 * 4 + int(v2 / 16)
            if(i+1 <= len) printf "%c", (v2 % 16) * 16 + int(v3 / 4)
            if(i+2 <= len) printf "%c", (v3 % 4) * 64 + v4
        }
    }'
}

# Function to mark order as complete
mark_complete() {
    local order_id=$1
    curl -k -s -X POST -H "X-API-Key: $API_KEY" \
        "https://friendlypos.vercel.app/api/print-queue/$order_id/complete" >/dev/null 2>&1
    echo "$(date) - Order $order_id marked as complete"
}

# Function to mark order as failed
mark_failed() {
    local order_id=$1
    local error_msg=$2
    curl -k -s -X POST -H "X-API-Key: $API_KEY" \
        -H "Content-Type: application/json" \
        -d "{\"error\":\"$error_msg\"}" \
        "https://friendlypos.vercel.app/api/print-queue/$order_id/fail" >/dev/null 2>&1
    echo "$(date) - Order $order_id marked as failed: $error_msg"
}

# Main loop
while true; do
    # Fetch pending orders
    RESPONSE=$(curl -k -s -H "X-API-Key: $API_KEY" "$API_URL" 2>&1)
    
    if [ $? -ne 0 ]; then
        echo "$(date) - ERROR: Failed to fetch orders from API"
        sleep $POLL_INTERVAL
        continue
    fi
    
    if [ ! -z "$RESPONSE" ] && [ "$RESPONSE" != "[]" ] && [ "$RESPONSE" != "null" ]; then
        echo "$(date) - Orders found"
        
        # Split array into individual orders
        ORDERS=$(echo "$RESPONSE" | sed 's/^\[//; s/\]$//' | sed 's/},{/}\n{/g')
        
        # Process each order
        echo "$ORDERS" | while IFS= read -r ORDER; do
            [ -z "$ORDER" ] && continue
            
            # Extract order ID
            ID=$(echo "$ORDER" | sed -n 's/.*"id":"\([^"]*\)".*/\1/p')
            [ -z "$ID" ] && ID=$(echo "$ORDER" | sed -n 's/.*"queue_id":\([0-9]*\).*/\1/p')
            
            if [ -z "$ID" ]; then
                echo "$(date) - WARNING: Could not extract order ID"
                continue
            fi
            
            # Extract printer IP
            PRINTER_IP=$(echo "$ORDER" | sed -n 's/.*"printer_ip":"\([^"]*\)".*/\1/p')
            [ -z "$PRINTER_IP" ] && PRINTER_IP=$(echo "$ORDER" | sed -n 's/.*"ip_address":"\([^"]*\)".*/\1/p')
            
            if [ -z "$PRINTER_IP" ]; then
                echo "$(date) - WARNING: No printer IP found for order $ID"
                continue
            fi
            
            # Extract printer port
            PRINTER_PORT=$(echo "$ORDER" | sed -n 's/.*"port":\([0-9]*\).*/\1/p')
            [ -z "$PRINTER_PORT" ] && PRINTER_PORT=$(echo "$ORDER" | sed -n 's/.*"printer_port":\([0-9]*\).*/\1/p')
            [ -z "$PRINTER_PORT" ] && PRINTER_PORT="9100"
            
            echo "$(date) - Processing order $ID for printer $PRINTER_IP:$PRINTER_PORT"
            
            # Extract print_data
            PRINT_DATA=$(echo "$ORDER" | sed -n 's/.*"print_data":"\([^"]*\)".*/\1/p')
            
            PRINT_SUCCESS=0
            
            if [ ! -z "$PRINT_DATA" ]; then
                echo "$(date) - Found print_data for order $ID"
                
                # Decode and send directly via awk + nc pipeline
                echo "$(date) - Decoding with awk and sending to printer"
                echo "$PRINT_DATA" | decode_base64_awk | nc $PRINTER_IP $PRINTER_PORT
                
                if [ $? -eq 0 ]; then
                    echo "$(date) - Order $ID sent to printer"
                    PRINT_SUCCESS=1
                else
                    echo "$(date) - ERROR: Failed to send order $ID"
                fi
                
            else
                echo "$(date) - No print_data found, using simple text mode"
                
                # Fallback: Simple working text
                ORDER_NUM=$(echo "$ORDER" | sed -n 's/.*"order_number":\([0-9]*\).*/\1/p')
                [ -z "$ORDER_NUM" ] && ORDER_NUM="$ID"
                
                # Use printf which we know works
                {
                    printf '\x1b\x40'  # Initialize
                    printf '\x1b\x61\x01'  # Center
                    printf 'ORDER #%s\n' "$ORDER_NUM"
                    printf '\x1b\x61\x00'  # Left
                    printf '========================\n'
                    
                    # Extract items
                    echo "$ORDER" | grep -o '"name":"[^"]*"' | cut -d'"' -f4 | while read ITEM; do
                        [ ! -z "$ITEM" ] && printf '- %s\n' "$ITEM"
                    done
                    
                    # Extract total
                    TOTAL=$(echo "$ORDER" | sed -n 's/.*"total":"\?\([0-9.]*\)"\?.*/\1/p')
                    if [ ! -z "$TOTAL" ]; then
                        printf '========================\n'
                        printf 'TOTAL: $%s\n' "$TOTAL"
                    fi
                    
                    printf '========================\n'
                    date "+%Y-%m-%d %H:%M:%S"
                    printf '\n\n\n\x1d\x56\x00'  # Feed and cut
                } | nc $PRINTER_IP $PRINTER_PORT
                
                if [ $? -eq 0 ]; then
                    echo "$(date) - Order $ID printed (text mode)"
                    PRINT_SUCCESS=1
                else
                    echo "$(date) - ERROR: Failed to print order $ID"
                fi
            fi
            
            # Update order status
            if [ $PRINT_SUCCESS -eq 1 ]; then
                mark_complete "$ID"
            else
                mark_failed "$ID" "Failed to print to $PRINTER_IP:$PRINTER_PORT"
            fi
            
            sleep 1
        done
    fi
    
    sleep $POLL_INTERVAL
done