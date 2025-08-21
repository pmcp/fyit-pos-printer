#!/bin/sh
# Teltonika Print Server - Binary Safe Version
# Saves decoded data to file first to preserve binary integrity

API_URL="https://friendlypos.vercel.app/api/print-queue"
API_KEY="d5a8262b7cfd8f46e599b36c584bb1ec16f28436680ddaa53f700e6d8a1765fa"
POLL_INTERVAL=2
LOG_FILE="/tmp/printserver.log"

exec >> "$LOG_FILE" 2>&1
echo "$(date) - Print Server Started (Binary Safe)"

# Function to decode base64 to file
decode_base64_to_file() {
    local input_data=$1
    local output_file=$2
    
    if command -v base64 >/dev/null 2>&1; then
        echo "$input_data" | base64 -d > "$output_file" 2>/dev/null || \
        echo "$input_data" | base64 > "$output_file"
    else
        # Awk fallback
        echo "$input_data" | awk '
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
        }' > "$output_file"
    fi
}

# Function to mark order as complete
mark_complete() {
    local order_id=$1
    local response
    
    response=$(curl -k -s -X POST -H "X-API-Key: $API_KEY" \
        "https://friendlypos.vercel.app/api/print-queue/$order_id/complete" 2>&1)
    
    if echo "$response" | grep -q '"error":true'; then
        local error_msg=$(echo "$response" | sed -n 's/.*"message":"\([^"]*\)".*/\1/p')
        echo "$(date) - ERROR: Failed to mark order $order_id as complete: ${error_msg:-Unknown error}"
        return 1
    else
        echo "$(date) - Order $order_id marked as complete"
        return 0
    fi
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
                echo "$(date) - Decoding print_data to binary file"
                
                # Save decoded data to binary file
                BINARY_FILE="/tmp/order_${ID}.bin"
                decode_base64_to_file "$PRINT_DATA" "$BINARY_FILE"
                
                # Check file was created and has content
                if [ -f "$BINARY_FILE" ] && [ -s "$BINARY_FILE" ]; then
                    echo "$(date) - Sending binary file to printer"
                    
                    # Send binary file to printer
                    cat "$BINARY_FILE" | nc $PRINTER_IP $PRINTER_PORT
                    
                    if [ $? -eq 0 ]; then
                        echo "$(date) - Order $ID printed successfully"
                        PRINT_SUCCESS=1
                    else
                        echo "$(date) - ERROR: Failed to send to printer"
                    fi
                    
                    # Clean up
                    rm -f "$BINARY_FILE"
                else
                    echo "$(date) - ERROR: Failed to decode print_data"
                fi
            else
                echo "$(date) - No print_data found, using fallback"
                
                # Fallback: Simple text printing
                ORDER_NUM=$(echo "$ORDER" | sed -n 's/.*"order_number":\([0-9]*\).*/\1/p')
                [ -z "$ORDER_NUM" ] && ORDER_NUM="$ID"
                
                {
                    printf '\x1b\x40'  # Initialize
                    echo "ORDER #$ORDER_NUM"
                    echo "========================"
                    echo "$ORDER" | grep -o '"name":"[^"]*"' | cut -d'"' -f4 | while read ITEM; do
                        [ ! -z "$ITEM" ] && echo "- $ITEM"
                    done
                    echo "========================"
                    date "+%Y-%m-%d %H:%M:%S"
                    printf '\n\n\n\x1d\x56\x00'  # Feed and cut
                } | nc $PRINTER_IP $PRINTER_PORT
                
                if [ $? -eq 0 ]; then
                    echo "$(date) - Order $ID printed successfully"
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