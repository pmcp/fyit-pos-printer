#!/bin/sh
# Teltonika RUT956 Print Server - With Init Fix
# Fixes print_data that has ESC @ at the end instead of beginning
# Copy to router: scp teltonika-print-server-fix.sh root@192.168.1.1:/root/print_server.sh

API_URL="https://friendlypos.vercel.app/api/print-queue"
API_KEY="d5a8262b7cfd8f46e599b36c584bb1ec16f28436680ddaa53f700e6d8a1765fa"
POLL_INTERVAL=2
LOG_FILE="/tmp/printserver.log"

# Redirect output to log file
exec >> "$LOG_FILE" 2>&1
echo "$(date) - Print Server Started (With Init Fix)"
echo "$(date) - API: $API_URL"
echo "$(date) - Poll interval: ${POLL_INTERVAL}s"

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
    
    if [ $? -eq 0 ]; then
        echo "$(date) - Order $order_id marked as failed: $error_msg"
    else
        echo "$(date) - WARNING: Failed to mark order $order_id as failed"
    fi
}

# Main loop
while true; do
    # Fetch pending orders
    RESPONSE=$(curl -s -H "X-API-Key: $API_KEY" "$API_URL" 2>&1)
    
    # Check for curl errors
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
            # Skip empty lines
            [ -z "$ORDER" ] && continue
            
            # Extract order ID
            ID=$(echo "$ORDER" | sed -n 's/.*"id":"\([^"]*\)".*/\1/p')
            if [ -z "$ID" ]; then
                ID=$(echo "$ORDER" | sed -n 's/.*"queue_id":\([0-9]*\).*/\1/p')
            fi
            
            if [ -z "$ID" ]; then
                echo "$(date) - WARNING: Could not extract order ID"
                continue
            fi
            
            # Extract printer IP
            PRINTER_IP=$(echo "$ORDER" | sed -n 's/.*"printer_ip":"\([^"]*\)".*/\1/p')
            if [ -z "$PRINTER_IP" ]; then
                PRINTER_IP=$(echo "$ORDER" | sed -n 's/.*"ip_address":"\([^"]*\)".*/\1/p')
            fi
            if [ -z "$PRINTER_IP" ]; then
                echo "$(date) - WARNING: No printer IP found for order $ID"
                continue
            fi
            
            # Extract printer port
            PRINTER_PORT=$(echo "$ORDER" | sed -n 's/.*"port":\([0-9]*\).*/\1/p')
            if [ -z "$PRINTER_PORT" ]; then
                PRINTER_PORT=$(echo "$ORDER" | sed -n 's/.*"printer_port":\([0-9]*\).*/\1/p')
            fi
            [ -z "$PRINTER_PORT" ] && PRINTER_PORT="9100"
            
            echo "$(date) - Processing order $ID for printer $PRINTER_IP:$PRINTER_PORT"
            
            # Extract print_data
            PRINT_DATA=$(echo "$ORDER" | sed -n 's/.*"print_data":"\([^"]*\)".*/\1/p')
            
            if [ -z "$PRINT_DATA" ]; then
                echo "$(date) - ERROR: No print_data found for order $ID"
                mark_failed "$ID" "No print data available"
                continue
            fi
            
            # FIX: Always start with ESC @ initialization
            # The POS system puts it at the end, we need it at the beginning
            echo "$(date) - Fixing ESC/POS initialization order"
            
            PRINT_SUCCESS=0
            
            # Method 1: Add init at start, remove from end if present
            (printf '\x1b\x40'; echo "$PRINT_DATA" | decode_base64 | head -c -2) | nc $PRINTER_IP $PRINTER_PORT
            
            if [ $? -eq 0 ]; then
                echo "$(date) - Order $ID printed successfully"
                PRINT_SUCCESS=1
            else
                echo "$(date) - ERROR: Failed to print order $ID"
            fi
            
            # Update order status
            if [ $PRINT_SUCCESS -eq 1 ]; then
                mark_complete "$ID"
            else
                mark_failed "$ID" "Failed to print to $PRINTER_IP:$PRINTER_PORT"
            fi
            
            # Small delay between orders
            sleep 1
        done
    fi
    
    # Wait before next poll
    sleep $POLL_INTERVAL
done