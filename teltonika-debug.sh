#!/bin/sh
# Debug script to test on Teltonika
# Run this on the Teltonika to see what's happening

echo "=== Print Server Debug Test ==="

# Test 1: Check if base64 works
echo "Test 1: Base64 decode test"
echo "SGVsbG8gV29ybGQK" | base64 -d 2>/dev/null || echo "SGVsbG8gV29ybGQK" | base64
echo ""

# Test 2: Send simple text directly
echo "Test 2: Sending plain text to printer"
PRINTER_IP="192.168.1.100"
PRINTER_PORT="9100"

echo "Testing connection to $PRINTER_IP:$PRINTER_PORT"
(echo "TEST PRINT"; printf '\n\n\n\x1d\x56\x00') | nc $PRINTER_IP $PRINTER_PORT
if [ $? -eq 0 ]; then
    echo "✓ Plain text sent"
else
    echo "✗ Failed to send"
fi
echo ""

# Test 3: Send basic ESC/POS
echo "Test 3: Sending basic ESC/POS commands"
(printf '\x1b\x40'; echo "ESC/POS TEST"; printf '\n\n\n\x1d\x56\x00') | nc $PRINTER_IP $PRINTER_PORT
if [ $? -eq 0 ]; then
    echo "✓ ESC/POS sent"
else
    echo "✗ Failed to send"
fi
echo ""

# Test 4: Get latest print_data from API and analyze
echo "Test 4: Fetching and analyzing print_data"
API_URL="https://friendlypos.vercel.app/api/print-queue"
API_KEY="d5a8262b7cfd8f46e599b36c584bb1ec16f28436680ddaa53f700e6d8a1765fa"

RESPONSE=$(curl -s -H "X-API-Key: $API_KEY" "$API_URL" | head -c 500)
echo "API Response (first 500 chars): $RESPONSE"
echo ""

# Extract first print_data
PRINT_DATA=$(echo "$RESPONSE" | sed -n 's/.*"print_data":"\([^"]*\)".*/\1/p' | head -1)
if [ ! -z "$PRINT_DATA" ]; then
    echo "Found print_data (first 50 chars): $(echo "$PRINT_DATA" | head -c 50)..."
    
    # Check what it starts with
    FIRST_4=$(echo "$PRINT_DATA" | head -c 4)
    echo "First 4 chars of base64: $FIRST_4"
    
    if [ "$FIRST_4" = "G3QS" ]; then
        echo "⚠️  OLD FORMAT DETECTED (starts with G3QS = ESC t 18)"
    elif [ "$FIRST_4" = "G0Ab" ]; then
        echo "✓ NEW FORMAT DETECTED (starts with G0Ab = ESC @)"
    else
        echo "? UNKNOWN FORMAT (starts with $FIRST_4)"
    fi
    
    # Decode and show hex
    echo ""
    echo "Hex dump of first 32 bytes:"
    echo "$PRINT_DATA" | base64 -d 2>/dev/null | hexdump -C | head -2
    
    # Try sending it
    echo ""
    echo "Test 5: Sending actual print_data to printer"
    echo "$PRINT_DATA" | base64 -d 2>/dev/null | nc $PRINTER_IP $PRINTER_PORT
    if [ $? -eq 0 ]; then
        echo "✓ Sent to printer"
    else
        echo "✗ Failed to send"
    fi
else
    echo "No print_data found in response"
fi

echo ""
echo "=== Debug Complete ==="
echo "Check what printed (if anything) and report back"