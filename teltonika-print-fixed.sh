#!/bin/sh
# Teltonika RUT956 Print Server - Binary Safe Fixed Version
# This version properly handles binary ESC/POS data from Base64

API_URL="https://friendlypos.vercel.app/api/print-queue"
API_KEY="d5a8262b7cfd8f46e599b36c584bb1ec16f28436680ddaa53f700e6d8a1765fa"
POLL_INTERVAL=2
LOG_FILE="/tmp/printserver.log"
DEBUG_MODE=1  # Set to 1 to enable debug output

# Redirect output to log file
exec >> "$LOG_FILE" 2>&1
echo "$(date) - Print Server Started (Binary Safe Fixed Version)"
echo "$(date) - API: $API_URL"
echo "$(date) - Poll interval: ${POLL_INTERVAL}s"

# Function to decode base64 to binary file
decode_base64_to_file() {
    local input_data="$1"
    local output_file="$2"
    
    # Method 1: Try base64 command first
    if command -v base64 >/dev/null 2>&1; then
        # Try with -d flag first (standard base64)
        if echo "$input_data" | base64 -d > "$output_file" 2>/dev/null; then
            echo "$(date) - Decoded using base64 -d"
            return 0
        fi
        # Try without -d flag (BusyBox base64)
        if echo "$input_data" | base64 > "$output_file" 2>/dev/null; then
            echo "$(date) - Decoded using base64 (BusyBox)"
            return 0
        fi
    fi
    
    # Method 2: Try using Python if available
    if command -v python3 >/dev/null 2>&1; then
        if python3 -c "import base64,sys; sys.stdout.buffer.write(base64.b64decode('$input_data'))" > "$output_file" 2>/dev/null; then
            echo "$(date) - Decoded using python3"
            return 0
        fi
    fi
    
    if command -v python >/dev/null 2>&1; then
        if python -c "import base64,sys; sys.stdout.write(base64.b64decode('$input_data'))" > "$output_file" 2>/dev/null; then
            echo "$(date) - Decoded using python"
            return 0
        fi
    fi
    
    # Method 3: Use awk as last resort
    echo "$input_data" | awk '
    BEGIN {
        b64="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
        for(i=0; i<64; i++) {
            b64_arr[substr(b64, i+1, 1)] = i
        }
    }
    {
        gsub(/=/, "")
        len = length($0)
        for(i=1; i<=len; i+=4) {
            c1 = substr($0, i, 1)
            c2 = substr($0, i+1, 1)
            c3 = substr($0, i+2, 1)
            c4 = substr($0, i+3, 1)
            
            n1 = (c1 in b64_arr) ? b64_arr[c1] : 0
            n2 = (c2 in b64_arr) ? b64_arr[c2] : 0
            n3 = (c3 in b64_arr) ? b64_arr[c3] : 0
            n4 = (c4 in b64_arr) ? b64_arr[c4] : 0
            
            printf "%c", n1 * 4 + int(n2 / 16)
            if(i+1 <= len) printf "%c", (n2 % 16) * 16 + int(n3 / 4)
            if(i+2 <= len) printf "%c", (n3 % 4) * 64 + n4
        }
    }' > "$output_file"
    
    if [ -s "$output_file" ]; then
        echo "$(date) - Decoded using awk"
        return 0
    fi
    
    echo "$(date) - ERROR: Failed to decode base64"
    return 1
}

# Function to verify ESC/POS data
verify_escpos_data() {
    local file="$1"
    
    if [ ! -f "$file" ] || [ ! -s "$file" ]; then
        echo "$(date) - ERROR: Binary file is empty or missing"
        return 1
    fi
    
    # Check if od or hexdump is available for debugging
    if [ "$DEBUG_MODE" = "1" ]; then
        if command -v od >/dev/null 2>&1; then
            echo "$(date) - First 16 bytes (hex):"
            od -An -tx1 -N 16 "$file" | head -1
        elif command -v hexdump >/dev/null 2>&1; then
            echo "$(date) - First 16 bytes (hex):"
            hexdump -C -n 16 "$file" | head -1
        fi
    fi
    
    # Check for ESC @ initialization (0x1B 0x40)
    if command -v od >/dev/null 2>&1; then
        FIRST_BYTES=$(od -An -tx1 -N 2 "$file" | tr -d ' ')
        if [ "$FIRST_BYTES" = "1b40" ]; then
            echo "$(date) - ✓ Valid ESC/POS data (starts with ESC @)"
            return 0
        fi
    fi
    
    # If we can't verify, assume it's valid if file has content
    FILE_SIZE=$(wc -c < "$file" 2>/dev/null || echo 0)
    if [ "$FILE_SIZE" -gt 10 ]; then
        echo "$(date) - File has $FILE_SIZE bytes, assuming valid"
        return 0
    fi
    
    echo "$(date) - WARNING: Could not verify ESC/POS data"
    return 1
}

# Function to send binary data to printer
send_to_printer() {
    local file="$1"
    local printer_ip="$2"
    local printer_port="$3"
    
    echo "$(date) - Sending binary data to $printer_ip:$printer_port"
    
    # Method 1: Using dd and nc for binary safety
    if command -v dd >/dev/null 2>&1; then
        dd if="$file" bs=1 2>/dev/null | nc "$printer_ip" "$printer_port"
        if [ $? -eq 0 ]; then
            echo "$(date) - Sent using dd + nc"
            return 0
        fi
    fi
    
    # Method 2: Using cat and nc
    cat "$file" | nc "$printer_ip" "$printer_port"
    if [ $? -eq 0 ]; then
        echo "$(date) - Sent using cat + nc"
        return 0
    fi
    
    echo "$(date) - ERROR: Failed to send data to printer"
    return 1
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
    # Fetch pending orders
    RESPONSE=$(curl -k -s -H "X-API-Key: $API_KEY" "$API_URL" 2>&1)
    
    # Check for curl errors
    if [ $? -ne 0 ]; then
        echo "$(date) - ERROR: Failed to fetch orders from API"
        sleep $POLL_INTERVAL
        continue
    fi
    
    if [ ! -z "$RESPONSE" ] && [ "$RESPONSE" != "[]" ] && [ "$RESPONSE" != "null" ]; then
        echo "$(date) - Orders found: $RESPONSE"
        
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
            
            if [ ! -z "$PRINT_DATA" ]; then
                echo "$(date) - Found print_data for order $ID"
                
                # Create temporary binary file
                BINARY_FILE="/tmp/order_${ID}.bin"
                
                # Decode base64 to binary file
                if decode_base64_to_file "$PRINT_DATA" "$BINARY_FILE"; then
                    
                    # Verify the decoded data
                    if verify_escpos_data "$BINARY_FILE"; then
                        
                        # Send to printer
                        if send_to_printer "$BINARY_FILE" "$PRINTER_IP" "$PRINTER_PORT"; then
                            echo "$(date) - Order $ID printed successfully"
                            PRINT_SUCCESS=1
                        else
                            echo "$(date) - ERROR: Failed to send order $ID to printer"
                        fi
                    else
                        echo "$(date) - ERROR: Invalid ESC/POS data for order $ID"
                    fi
                else
                    echo "$(date) - ERROR: Failed to decode print_data for order $ID"
                fi
                
                # Clean up binary file (keep for debugging if needed)
                if [ "$DEBUG_MODE" = "1" ]; then
                    echo "$(date) - Debug: Binary file kept at $BINARY_FILE"
                else
                    rm -f "$BINARY_FILE"
                fi
                
            else
                echo "$(date) - No print_data found for order $ID, using fallback text mode"
                
                # Fallback: Generate simple text receipt
                ORDER_NUM=$(echo "$ORDER" | sed -n 's/.*"order_number":\([0-9]*\).*/\1/p')
                [ -z "$ORDER_NUM" ] && ORDER_NUM="$ID"
                
                TEMP_FILE="/tmp/order_${ID}_text.txt"
                {
                    printf '\x1b\x40'  # Initialize printer
                    printf '\x1b\x61\x01'  # Center align
                    echo "ORDER #$ORDER_NUM"
                    printf '\x1b\x61\x00'  # Left align
                    echo "========================"
                    
                    # Extract and print items
                    echo "$ORDER" | grep -o '"name":"[^"]*"' | cut -d'"' -f4 | while read ITEM; do
                        [ ! -z "$ITEM" ] && echo "- $ITEM"
                    done
                    
                    # Extract total if available
                    TOTAL=$(echo "$ORDER" | sed -n 's/.*"total":"\?\([0-9.]*\)"\?.*/\1/p')
                    if [ ! -z "$TOTAL" ]; then
                        echo "========================"
                        echo "TOTAL: \$$TOTAL"
                    fi
                    
                    echo "========================"
                    date "+%Y-%m-%d %H:%M:%S"
                    printf '\n\n\n\x1d\x56\x00'  # Feed and cut
                } > "$TEMP_FILE"
                
                # Send text file to printer
                if send_to_printer "$TEMP_FILE" "$PRINTER_IP" "$PRINTER_PORT"; then
                    echo "$(date) - Order $ID printed successfully (text mode)"
                    PRINT_SUCCESS=1
                else
                    echo "$(date) - ERROR: Failed to print order $ID (text mode)"
                fi
                
                rm -f "$TEMP_FILE"
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