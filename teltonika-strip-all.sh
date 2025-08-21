#!/bin/sh
# Teltonika Print Server - Strip ALL ESC/POS Commands
# Removes all control characters, keeps only text

API_URL="https://friendlypos.vercel.app/api/print-queue"
API_KEY="d5a8262b7cfd8f46e599b36c584bb1ec16f28436680ddaa53f700e6d8a1765fa"
POLL_INTERVAL=2
LOG_FILE="/tmp/printserver.log"

exec >> "$LOG_FILE" 2>&1
echo "$(date) - Print Server Started (Strip All ESC/POS)"

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
    RESPONSE=$(curl -k -s -H "X-API-Key: $API_KEY" "$API_URL" 2>&1)
    
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
            
            if [ ! -z "$PRINT_DATA" ]; then
                echo "$(date) - Stripping all ESC/POS and sending text only"
                
                # Decode and extract only printable text
                TEMP_FILE="/tmp/order_${ID}_text.txt"
                
                # Decode and use strings to extract only text
                echo "$PRINT_DATA" | decode_base64 | strings > "$TEMP_FILE"
                
                # Add some formatting back
                {
                    echo "================================"
                    cat "$TEMP_FILE"
                    echo "================================"
                    printf "\n\n\n\n\n"
                } | nc $PRINTER_IP $PRINTER_PORT
                
                if [ $? -eq 0 ]; then
                    echo "$(date) - Order $ID sent successfully"
                    mark_complete "$ID"
                else
                    echo "$(date) - ERROR: Failed to send order $ID"
                    mark_failed "$ID" "Failed to print"
                fi
                
                rm -f "$TEMP_FILE"
            else
                # Fallback: extract from JSON
                ORDER_NUM=$(echo "$ORDER" | sed -n 's/.*"order_number":\([0-9]*\).*/\1/p')
                [ -z "$ORDER_NUM" ] && ORDER_NUM="$ID"
                
                CUSTOMER=$(echo "$ORDER" | sed -n 's/.*"customer":{[^}]*"name":"\([^"]*\)".*/\1/p')
                TOTAL=$(echo "$ORDER" | sed -n 's/.*"total":"\?\([0-9.]*\)"\?.*/\1/p')
                LOCATION=$(echo "$ORDER" | sed -n 's/.*"location":"\([^"]*\)".*/\1/p')
                
                {
                    echo "================================"
                    [ ! -z "$LOCATION" ] && echo "$LOCATION"
                    echo "Order #$ORDER_NUM"
                    echo "$(date '+%Y-%m-%d %H:%M')"
                    [ ! -z "$CUSTOMER" ] && echo "Customer: $CUSTOMER"
                    echo "================================"
                    
                    echo "$ORDER" | grep -o '"name":"[^"]*"' | cut -d'"' -f4 | while read ITEM; do
                        [ ! -z "$ITEM" ] && echo "  $ITEM"
                    done
                    
                    echo "================================"
                    [ ! -z "$TOTAL" ] && echo "TOTAL: \$$TOTAL"
                    echo ""
                    echo "Thank You!"
                    printf "\n\n\n\n\n"
                } | nc $PRINTER_IP $PRINTER_PORT
                
                if [ $? -eq 0 ]; then
                    echo "$(date) - Order $ID sent successfully"
                    mark_complete "$ID"
                else
                    echo "$(date) - ERROR: Failed to send order $ID"
                    mark_failed "$ID" "Failed to print"
                fi
            fi
            
            sleep 1
        done
    fi
    
    sleep $POLL_INTERVAL
done