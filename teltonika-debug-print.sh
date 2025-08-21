#!/bin/sh
# Debug version - saves what we're sending to a file so we can inspect it

API_URL="https://friendlypos.vercel.app/api/print-queue"
API_KEY="d5a8262b7cfd8f46e599b36c584bb1ec16f28436680ddaa53f700e6d8a1765fa"
POLL_INTERVAL=2
LOG_FILE="/tmp/printserver.log"

exec >> "$LOG_FILE" 2>&1
echo "$(date) - Print Server Started (Debug Version)"

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
            
            echo "$(date) - Processing order $ID"
            
            # Extract order details
            ORDER_NUM=$(echo "$ORDER" | sed -n 's/.*"order_number":\([0-9]*\).*/\1/p')
            [ -z "$ORDER_NUM" ] && ORDER_NUM="$ID"
            
            # Create simple receipt and save to file for debugging
            DEBUG_FILE="/tmp/order_${ID}.txt"
            
            # Method 1: Using printf for everything
            {
                printf "Order #%s\n" "$ORDER_NUM"
                printf "Time: %s\n" "$(date '+%Y-%m-%d %H:%M')"
                printf "================================\n"
                printf "Test Item 1\n"
                printf "Test Item 2\n"
                printf "================================\n"
                printf "TOTAL: \$25.00\n"
                printf "\n"
                printf "Thank You!\n"
                printf "\n\n\n\n"
            } > "$DEBUG_FILE"
            
            echo "$(date) - Saved receipt to $DEBUG_FILE"
            echo "$(date) - Content:"
            cat "$DEBUG_FILE"
            
            # Send using cat and nc
            echo "$(date) - Sending to printer using: cat $DEBUG_FILE | nc $PRINTER_IP $PRINTER_PORT"
            cat "$DEBUG_FILE" | nc $PRINTER_IP $PRINTER_PORT
            
            if [ $? -eq 0 ]; then
                echo "$(date) - Order $ID sent successfully"
                mark_complete "$ID"
                
                # Also try sending with printf directly
                echo "$(date) - Testing direct printf send:"
                printf "DIRECT TEST FOR ORDER %s\n\n\n" "$ID" | nc $PRINTER_IP $PRINTER_PORT
            else
                echo "$(date) - ERROR: Failed to send order $ID"
                mark_failed "$ID" "Failed to print"
            fi
            
            sleep 1
        done
    fi
    
    sleep $POLL_INTERVAL
done