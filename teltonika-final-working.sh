#!/bin/sh
# Teltonika Print Server - Final Working Version for TM-m30
# Generates clean receipts, ignoring print_data from POS

API_URL="https://friendlypos.vercel.app/api/print-queue"
API_KEY="d5a8262b7cfd8f46e599b36c584bb1ec16f28436680ddaa53f700e6d8a1765fa"
POLL_INTERVAL=2
LOG_FILE="/tmp/printserver.log"

exec >> "$LOG_FILE" 2>&1
echo "$(date) - Print Server Started (Final Working Version)"

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
            
            # Extract order details
            ORDER_NUM=$(echo "$ORDER" | sed -n 's/.*"order_number":\([0-9]*\).*/\1/p')
            [ -z "$ORDER_NUM" ] && ORDER_NUM="$ID"
            
            CUSTOMER=$(echo "$ORDER" | sed -n 's/.*"customer":{[^}]*"name":"\([^"]*\)".*/\1/p')
            TOTAL=$(echo "$ORDER" | sed -n 's/.*"total":"\?\([0-9.]*\)"\?.*/\1/p')
            LOCATION=$(echo "$ORDER" | sed -n 's/.*"location":"\([^"]*\)".*/\1/p')
            
            # Create receipt file using printf (which we know works)
            RECEIPT_FILE="/tmp/receipt_${ID}.txt"
            
            {
                # Simple ESC/POS init
                printf '\x1b\x40'
                
                # Location/header
                if [ ! -z "$LOCATION" ]; then
                    printf '\x1b\x21\x08'  # Bold
                    printf '%s\n' "$LOCATION"
                    printf '\x1b\x21\x00'  # Normal
                    printf '\n'
                fi
                
                # Order info
                printf 'Order #%s\n' "$ORDER_NUM"
                printf '%s\n' "$(date '+%Y-%m-%d %H:%M:%S')"
                
                if [ ! -z "$CUSTOMER" ]; then
                    printf 'Customer: %s\n' "$CUSTOMER"
                fi
                
                printf '================================\n'
                
                # Items - extract each item name
                ITEMS_FOUND=0
                echo "$ORDER" | sed 's/.*"items":\[\([^]]*\)\].*/\1/' | sed 's/},{/}\n{/g' | while IFS= read -r item_json; do
                    ITEM_NAME=$(echo "$item_json" | sed -n 's/.*"name":"\([^"]*\)".*/\1/p')
                    ITEM_QTY=$(echo "$item_json" | sed -n 's/.*"quantity":\([0-9]*\).*/\1/p')
                    ITEM_PRICE=$(echo "$item_json" | sed -n 's/.*"price":"\?\([0-9.]*\)"\?.*/\1/p')
                    
                    if [ ! -z "$ITEM_NAME" ]; then
                        [ -z "$ITEM_QTY" ] && ITEM_QTY="1"
                        if [ ! -z "$ITEM_PRICE" ]; then
                            printf '  %sx %-20s $%s\n' "$ITEM_QTY" "$ITEM_NAME" "$ITEM_PRICE"
                        else
                            printf '  %sx %s\n' "$ITEM_QTY" "$ITEM_NAME"
                        fi
                        ITEMS_FOUND=1
                    fi
                done
                
                # Fallback if no items parsed correctly
                if [ "$ITEMS_FOUND" = "0" ]; then
                    echo "$ORDER" | grep -o '"name":"[^"]*"' | cut -d'"' -f4 | while read ITEM; do
                        if [ ! -z "$ITEM" ]; then
                            printf '  %s\n' "$ITEM"
                        fi
                    done
                fi
                
                printf '================================\n'
                
                # Total
                if [ ! -z "$TOTAL" ]; then
                    printf '\x1b\x21\x08'  # Bold
                    printf 'TOTAL: $%s\n' "$TOTAL"
                    printf '\x1b\x21\x00'  # Normal
                fi
                
                printf '\n'
                printf 'Thank You!\n'
                
                # Feed and cut
                printf '\n\n\n\n'
                printf '\x1d\x56\x00'  # Cut
                
            } > "$RECEIPT_FILE"
            
            # Send the file to printer
            cat "$RECEIPT_FILE" | nc $PRINTER_IP $PRINTER_PORT
            
            if [ $? -eq 0 ]; then
                echo "$(date) - Order $ID printed successfully"
                mark_complete "$ID"
                rm -f "$RECEIPT_FILE"
            else
                echo "$(date) - ERROR: Failed to print order $ID"
                mark_failed "$ID" "Failed to print to $PRINTER_IP:$PRINTER_PORT"
            fi
            
            sleep 1
        done
    fi
    
    sleep $POLL_INTERVAL
done