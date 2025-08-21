#!/bin/sh
# Teltonika Print Server - Clean Version
# Removes problematic ESC/POS commands while preserving text

API_URL="https://friendlypos.vercel.app/api/print-queue"
API_KEY="d5a8262b7cfd8f46e599b36c584bb1ec16f28436680ddaa53f700e6d8a1765fa"
POLL_INTERVAL=2
LOG_FILE="/tmp/printserver.log"

exec >> "$LOG_FILE" 2>&1
echo "$(date) - Print Server Started (Clean Filter)"

# Function to decode base64
decode_base64() {
    base64 -d 2>/dev/null || base64
}

# Function to mark order as complete
mark_complete() {
    local order_id=$1
    local response
    
    response=$(curl -s -X POST -H "X-API-Key: $API_KEY" \
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
            
            if [ -z "$PRINT_DATA" ]; then
                echo "$(date) - ERROR: No print_data found for order $ID"
                mark_failed "$ID" "No print data available"
                continue
            fi
            
            echo "$(date) - Cleaning and sending print data"
            
            # Clean the print data by replacing problematic commands with safer ones
            # Save to temp file for processing
            TEMP_FILE="/tmp/print_$ID.bin"
            echo "$PRINT_DATA" | decode_base64 > "$TEMP_FILE"
            
            # Send cleaned data to printer
            # Using xxd to replace specific hex sequences if available
            if command -v xxd >/dev/null 2>&1; then
                # Replace ESC ! 0x10 with ESC ! 0x08 (bold instead of double height)
                # Replace ESC ! 0x20 with ESC ! 0x08 (bold instead of double width)
                # Remove ESC d 0x04
                xxd -p "$TEMP_FILE" | \
                    sed 's/1b2110/1b2108/g; s/1b2120/1b2108/g; s/1b2130/1b2108/g; s/1b6404//g' | \
                    xxd -r -p | nc $PRINTER_IP $PRINTER_PORT
            else
                # Fallback: just send as-is but with simple replacements
                cat "$TEMP_FILE" | \
                    tr '\033!0\033! \033!P' '\033!\010\033!\010\033!\010' | \
                    nc $PRINTER_IP $PRINTER_PORT
            fi
            
            PRINT_SUCCESS=$?
            rm -f "$TEMP_FILE"
            
            if [ $PRINT_SUCCESS -eq 0 ]; then
                echo "$(date) - Order $ID printed successfully"
                mark_complete "$ID"
            else
                echo "$(date) - ERROR: Failed to print order $ID"
                mark_failed "$ID" "Failed to print to $PRINTER_IP:$PRINTER_PORT"
            fi
            
            sleep 1
        done
    fi
    
    sleep $POLL_INTERVAL
done