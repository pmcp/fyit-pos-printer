#!/bin/sh
# Teltonika RUT956 Print Server Script - Fixed Version
# This script runs on the Teltonika router to poll orders and print them
# Copy this to the router with: scp teltonika-print-server-fixed.sh root@192.168.1.1:/root/print_server.sh

API_URL="https://friendlypos.vercel.app/api/print-queue"
API_KEY="d5a8262b7cfd8f46e599b36c584bb1ec16f28436680ddaa53f700e6d8a1765fa"
POLL_INTERVAL=2
LOG_FILE="/tmp/printserver.log"

# Redirect output to log file
exec >> "$LOG_FILE" 2>&1
echo "$(date) - Print Server Started (Fixed Version)"
echo "$(date) - API: $API_URL"
echo "$(date) - Poll interval: ${POLL_INTERVAL}s"

# Function to decode base64 (tries base64 command first, falls back to awk)
decode_base64() {
    if command -v base64 >/dev/null 2>&1; then
        # BusyBox base64 doesn't support -d flag, use stdin/stdout directly
        base64 -d 2>/dev/null || base64
    else
        # Fallback to awk for BusyBox systems without base64
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
    local response
    
    response=$(curl -s -X POST -H "X-API-Key: $API_KEY" \
        "https://friendlypos.vercel.app/api/print-queue/$order_id/complete" 2>&1)
    
    # Check if response contains error
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

# Function to print with fixed ESC/POS commands
print_fixed_data() {
    local printer_ip=$1
    local printer_port=$2
    local print_data=$3
    
    # Method 1: Send the decoded data as-is first
    echo "$print_data" | decode_base64 | nc $printer_ip $printer_port
    return $?
}

# Function to create simple receipt
print_simple_receipt() {
    local printer_ip=$1
    local printer_port=$2
    local order_id=$3
    local order_data=$4
    
    echo "$(date) - Creating simple receipt for order $order_id"
    
    # Extract order details
    ORDER_NUM=$(echo "$order_data" | sed -n 's/.*"order_number":\([0-9]*\).*/\1/p')
    [ -z "$ORDER_NUM" ] && ORDER_NUM="$order_id"
    
    CUSTOMER=$(echo "$order_data" | sed -n 's/.*"customer":{[^}]*"name":"\([^"]*\)".*/\1/p')
    TOTAL=$(echo "$order_data" | sed -n 's/.*"total":"\?\([0-9.]*\)"\?.*/\1/p')
    LOCATION=$(echo "$order_data" | sed -n 's/.*"location":"\([^"]*\)".*/\1/p')
    
    # Send simple formatted receipt
    (
        # Initialize printer and reset
        printf '\x1b\x40'
        
        # Title - centered and double height
        printf '\x1b\x61\x01'        # Center align
        printf '\x1b\x21\x30'        # Double height + width
        [ ! -z "$LOCATION" ] && printf '%s\n' "$LOCATION"
        printf '\x1b\x21\x00'        # Normal size
        printf '\n'
        
        # Order info
        printf '\x1b\x61\x00'        # Left align
        printf 'Order #%s\n' "$ORDER_NUM"
        printf '%s\n' "$(date '+%Y-%m-%d %H:%M:%S')"
        [ ! -z "$CUSTOMER" ] && printf 'Customer: %s\n' "$CUSTOMER"
        printf '================================\n'
        
        # Items - parse JSON array
        echo "$order_data" | sed -n 's/.*"items":\[\([^]]*\)\].*/\1/p' | sed 's/},{/}\n{/g' | while IFS= read -r item; do
            ITEM_NAME=$(echo "$item" | sed -n 's/.*"name":"\([^"]*\)".*/\1/p')
            ITEM_QTY=$(echo "$item" | sed -n 's/.*"quantity":\([0-9]*\).*/\1/p')
            ITEM_PRICE=$(echo "$item" | sed -n 's/.*"price":"\?\([0-9.]*\)"\?.*/\1/p')
            
            if [ ! -z "$ITEM_NAME" ]; then
                [ -z "$ITEM_QTY" ] && ITEM_QTY="1"
                if [ ! -z "$ITEM_PRICE" ]; then
                    printf '%sx %-20s $%s\n' "$ITEM_QTY" "$ITEM_NAME" "$ITEM_PRICE"
                else
                    printf '%sx %s\n' "$ITEM_QTY" "$ITEM_NAME"
                fi
            fi
        done
        
        printf '================================\n'
        
        # Total
        if [ ! -z "$TOTAL" ]; then
            printf '\x1b\x21\x08'    # Bold
            printf 'TOTAL:                  $%s\n' "$TOTAL"
            printf '\x1b\x21\x00'    # Normal
        fi
        
        # Footer
        printf '\n'
        printf '\x1b\x61\x01'        # Center
        printf 'Thank You!\n'
        printf '\x1b\x61\x00'        # Left
        
        # Feed and cut
        printf '\n\n\n\n'
        printf '\x1d\x56\x00'        # Cut
    ) | nc $printer_ip $printer_port
    
    return $?
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
            
            # Extract printer IP (try multiple field names)
            PRINTER_IP=$(echo "$ORDER" | sed -n 's/.*"printer_ip":"\([^"]*\)".*/\1/p')
            if [ -z "$PRINTER_IP" ]; then
                PRINTER_IP=$(echo "$ORDER" | sed -n 's/.*"ip_address":"\([^"]*\)".*/\1/p')
            fi
            if [ -z "$PRINTER_IP" ]; then
                echo "$(date) - WARNING: No printer IP found for order $ID, skipping"
                continue
            fi
            
            # Extract printer port (default to 9100)
            PRINTER_PORT=$(echo "$ORDER" | sed -n 's/.*"port":\([0-9]*\).*/\1/p')
            if [ -z "$PRINTER_PORT" ]; then
                PRINTER_PORT=$(echo "$ORDER" | sed -n 's/.*"printer_port":\([0-9]*\).*/\1/p')
            fi
            [ -z "$PRINTER_PORT" ] && PRINTER_PORT="9100"
            
            echo "$(date) - Processing order $ID for printer $PRINTER_IP:$PRINTER_PORT"
            
            # Extract print_data (pre-formatted base64 ESC/POS commands)
            PRINT_DATA=$(echo "$ORDER" | sed -n 's/.*"print_data":"\([^"]*\)".*/\1/p')
            
            PRINT_SUCCESS=0
            
            # Try method 1: Use provided print_data if available
            if [ ! -z "$PRINT_DATA" ]; then
                echo "$(date) - Attempting to use pre-formatted print_data"
                
                if print_fixed_data "$PRINTER_IP" "$PRINTER_PORT" "$PRINT_DATA"; then
                    echo "$(date) - Order $ID printed successfully using print_data"
                    PRINT_SUCCESS=1
                else
                    echo "$(date) - Failed with print_data, trying simple format"
                    # Try method 2: Simple formatted receipt
                    if print_simple_receipt "$PRINTER_IP" "$PRINTER_PORT" "$ID" "$ORDER"; then
                        echo "$(date) - Order $ID printed successfully using simple format"
                        PRINT_SUCCESS=1
                    else
                        echo "$(date) - ERROR: Failed to print order $ID"
                    fi
                fi
            else
                # No print_data, use simple format
                echo "$(date) - No print_data found, using simple format"
                if print_simple_receipt "$PRINTER_IP" "$PRINTER_PORT" "$ID" "$ORDER"; then
                    echo "$(date) - Order $ID printed successfully using simple format"
                    PRINT_SUCCESS=1
                else
                    echo "$(date) - ERROR: Failed to print order $ID"
                fi
            fi
            
            # Update order status based on print result
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