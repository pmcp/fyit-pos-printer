#!/bin/sh
# Teltonika Print Server - AWK Base64 Decoder Version with Better Error Handling
# This version handles API timeouts and retries more gracefully

API_URL="https://friendlypos.vercel.app/api/print-queue"
API_KEY="d5a8262b7cfd8f46e599b36c584bb1ec16f28436680ddaa53f700e6d8a1765fa"
POLL_INTERVAL=2
LOG_FILE="/tmp/printserver.log"
CURL_TIMEOUT=10  # Timeout for curl commands

# Redirect output to log file
exec >> "$LOG_FILE" 2>&1
echo "$(date) - Print Server Started (AWK Decoder with Error Handling)"

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

# Function to mark order as complete with retries
mark_complete() {
    local order_id=$1
    local attempts=0
    local max_attempts=3
    
    while [ $attempts -lt $max_attempts ]; do
        attempts=$((attempts + 1))
        
        # Try to mark complete with timeout
        response=$(curl -k -s -m $CURL_TIMEOUT -X POST -H "X-API-Key: $API_KEY" \
            "https://friendlypos.vercel.app/api/print-queue/$order_id/complete" 2>&1)
        
        if [ $? -eq 0 ]; then
            # Check if response contains error
            if echo "$response" | grep -q '"error":true'; then
                echo "$(date) - WARNING: API returned error for order $order_id (attempt $attempts/$max_attempts)"
                if [ $attempts -lt $max_attempts ]; then
                    sleep 2
                    continue
                fi
            else
                echo "$(date) - Order $order_id marked as complete"
                return 0
            fi
        else
            echo "$(date) - WARNING: Failed to mark order $order_id complete (attempt $attempts/$max_attempts)"
            if [ $attempts -lt $max_attempts ]; then
                sleep 2
                continue
            fi
        fi
    done
    
    echo "$(date) - ERROR: Could not mark order $order_id complete after $max_attempts attempts"
    return 1
}

# Function to mark order as failed
mark_failed() {
    local order_id=$1
    local error_msg=$2
    
    curl -k -s -m $CURL_TIMEOUT -X POST -H "X-API-Key: $API_KEY" \
        -H "Content-Type: application/json" \
        -d "{\"error\":\"$error_msg\"}" \
        "https://friendlypos.vercel.app/api/print-queue/$order_id/fail" >/dev/null 2>&1
    
    if [ $? -eq 0 ]; then
        echo "$(date) - Order $order_id marked as failed: $error_msg"
    else
        echo "$(date) - WARNING: Could not mark order $order_id as failed"
    fi
}

# Track processed orders to avoid duplicates
PROCESSED_ORDERS_FILE="/tmp/processed_orders.txt"
touch "$PROCESSED_ORDERS_FILE"

# Function to check if order was already processed
is_order_processed() {
    local order_id=$1
    grep -q "^$order_id$" "$PROCESSED_ORDERS_FILE"
}

# Function to mark order as processed
mark_order_processed() {
    local order_id=$1
    echo "$order_id" >> "$PROCESSED_ORDERS_FILE"
    
    # Keep only last 100 orders to prevent file from growing too large
    tail -100 "$PROCESSED_ORDERS_FILE" > "$PROCESSED_ORDERS_FILE.tmp"
    mv "$PROCESSED_ORDERS_FILE.tmp" "$PROCESSED_ORDERS_FILE"
}

# Main loop
while true; do
    # Fetch pending orders with timeout
    RESPONSE=$(curl -k -s -m $CURL_TIMEOUT -H "X-API-Key: $API_KEY" "$API_URL" 2>&1)
    
    if [ $? -ne 0 ]; then
        echo "$(date) - ERROR: Failed to fetch orders from API"
        sleep $POLL_INTERVAL
        continue
    fi
    
    if [ ! -z "$RESPONSE" ] && [ "$RESPONSE" != "[]" ] && [ "$RESPONSE" != "null" ]; then
        # Don't log the full response every time - just count
        ORDER_COUNT=$(echo "$RESPONSE" | grep -o '"id"' | wc -l)
        echo "$(date) - Found $ORDER_COUNT order(s) to process"
        
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
            
            # Skip if already processed
            if is_order_processed "$ID"; then
                echo "$(date) - Skipping already processed order $ID"
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
                # Decode and send directly via awk + nc pipeline
                echo "$PRINT_DATA" | decode_base64_awk | nc $PRINTER_IP $PRINTER_PORT
                
                if [ $? -eq 0 ]; then
                    echo "$(date) - Order $ID sent to printer"
                    PRINT_SUCCESS=1
                else
                    echo "$(date) - ERROR: Failed to send order $ID to printer"
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
                    echo "$(date) - Order $ID sent to printer (text mode)"
                    PRINT_SUCCESS=1
                else
                    echo "$(date) - ERROR: Failed to print order $ID"
                fi
            fi
            
            # Mark order as processed to avoid duplicates
            mark_order_processed "$ID"
            
            # Update order status immediately after printing
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