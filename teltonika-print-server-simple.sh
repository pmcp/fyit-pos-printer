#!/bin/sh
# Teltonika RUT956 Print Server - Simple Version
# Ignores print_data and creates clean receipts
# Copy to router: scp teltonika-print-server-simple.sh root@192.168.1.1:/root/print_server.sh

API_URL="https://friendlypos.vercel.app/api/print-queue"
API_KEY="d5a8262b7cfd8f46e599b36c584bb1ec16f28436680ddaa53f700e6d8a1765fa"
POLL_INTERVAL=2
LOG_FILE="/tmp/printserver.log"

# Redirect output to log file
exec >> "$LOG_FILE" 2>&1
echo "$(date) - Print Server Started (Simple Version - Ignoring print_data)"
echo "$(date) - API: $API_URL"
echo "$(date) - Poll interval: ${POLL_INTERVAL}s"

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
            echo "$(date) - IGNORING print_data field, creating clean receipt"
            
            # Extract order details
            ORDER_NUM=$(echo "$ORDER" | sed -n 's/.*"order_number":\([0-9]*\).*/\1/p')
            [ -z "$ORDER_NUM" ] && ORDER_NUM="$ID"
            
            CUSTOMER=$(echo "$ORDER" | sed -n 's/.*"customer":{[^}]*"name":"\([^"]*\)".*/\1/p')
            TOTAL=$(echo "$ORDER" | sed -n 's/.*"total":"\?\([0-9.]*\)"\?.*/\1/p')
            LOCATION=$(echo "$ORDER" | sed -n 's/.*"location":"\([^"]*\)".*/\1/p')
            
            # Create and send clean receipt
            PRINT_SUCCESS=0
            (
                # Reset printer
                printf '\x1b\x40'
                
                # Header
                if [ ! -z "$LOCATION" ]; then
                    printf '\x1b\x61\x01'    # Center
                    printf '\x1b\x21\x10'    # Double height
                    printf '%s\n' "$LOCATION"
                    printf '\x1b\x21\x00'    # Normal
                    printf '\n'
                fi
                
                # Order info
                printf '\x1b\x61\x00'        # Left align
                printf 'Order #%s\n' "$ORDER_NUM"
                printf '%s\n' "$(date '+%m/%d/%Y %I:%M %p')"
                
                if [ ! -z "$CUSTOMER" ]; then
                    printf 'Customer: %s\n' "$CUSTOMER"
                fi
                
                printf '--------------------------------\n'
                
                # Parse and print items
                echo "$ORDER" | grep -o '"name":"[^"]*"' | while IFS= read -r name_match; do
                    ITEM_NAME=$(echo "$name_match" | cut -d'"' -f4)
                    if [ ! -z "$ITEM_NAME" ]; then
                        printf '  %s\n' "$ITEM_NAME"
                    fi
                done
                
                printf '--------------------------------\n'
                
                # Total
                if [ ! -z "$TOTAL" ]; then
                    printf '\x1b\x21\x08'    # Bold
                    printf 'TOTAL: $%s\n' "$TOTAL"
                    printf '\x1b\x21\x00'    # Normal
                fi
                
                # Footer
                printf '\n'
                printf '\x1b\x61\x01'        # Center
                printf 'Thank You!\n'
                printf '\x1b\x61\x00'        # Left
                
                # Feed and cut
                printf '\n\n\n'
                printf '\x1d\x56\x00'
                
            ) | nc $PRINTER_IP $PRINTER_PORT
            
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