#!/bin/sh
# Teltonika Print Server - Known Working Method
# Uses printf and file method that we confirmed works

API_URL="https://friendlypos.vercel.app/api/print-queue"
API_KEY="d5a8262b7cfd8f46e599b36c584bb1ec16f28436680ddaa53f700e6d8a1765fa"
POLL_INTERVAL=2
LOG_FILE="/tmp/printserver.log"

exec >> "$LOG_FILE" 2>&1
echo "$(date) - Print Server Started (Working Method)"

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
            
            echo "$(date) - Processing order $ID"
            
            # Extract order details
            ORDER_NUM=$(echo "$ORDER" | sed -n 's/.*"order_number":\([0-9]*\).*/\1/p')
            [ -z "$ORDER_NUM" ] && ORDER_NUM="$ID"
            
            CUSTOMER=$(echo "$ORDER" | sed -n 's/.*"customer":{[^}]*"name":"\([^"]*\)".*/\1/p')
            TOTAL=$(echo "$ORDER" | sed -n 's/.*"total":"\?\([0-9.]*\)"\?.*/\1/p')
            LOCATION=$(echo "$ORDER" | sed -n 's/.*"location":"\([^"]*\)".*/\1/p')
            
            # Create receipt using printf (which we know works)
            RECEIPT_FILE="/tmp/order_${ID}.txt"
            
            # Use printf for everything - NO ESC/POS, just plain text
            {
                printf "================================\n"
                if [ ! -z "$LOCATION" ]; then
                    printf "%s\n" "$LOCATION"
                    printf "\n"
                fi
                printf "Order #%s\n" "$ORDER_NUM"
                printf "Time: %s\n" "$(date '+%Y-%m-%d %H:%M')"
                if [ ! -z "$CUSTOMER" ]; then
                    printf "Customer: %s\n" "$CUSTOMER"
                fi
                printf "================================\n"
                
                # Extract items
                echo "$ORDER" | grep -o '"name":"[^"]*"' | cut -d'"' -f4 | while read ITEM; do
                    if [ ! -z "$ITEM" ]; then
                        printf "  %s\n" "$ITEM"
                    fi
                done
                
                printf "================================\n"
                if [ ! -z "$TOTAL" ]; then
                    printf "TOTAL: \$%s\n" "$TOTAL"
                fi
                printf "\n"
                printf "Thank You!\n"
                printf "\n\n\n\n\n"
            } > "$RECEIPT_FILE"
            
            # Send the file to printer
            cat "$RECEIPT_FILE" | nc $PRINTER_IP $PRINTER_PORT
            
            if [ $? -eq 0 ]; then
                echo "$(date) - Order $ID sent successfully"
                mark_complete "$ID"
                rm -f "$RECEIPT_FILE"
            else
                echo "$(date) - ERROR: Failed to send order $ID"
                mark_failed "$ID" "Failed to print"
            fi
            
            sleep 1
        done
    fi
    
    sleep $POLL_INTERVAL
done