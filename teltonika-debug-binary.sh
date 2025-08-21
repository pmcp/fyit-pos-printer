#!/bin/sh
# Debug script to test binary data transmission on Teltonika

echo "=== Teltonika Binary Transmission Debug ==="
echo ""

# Test print data from user
PRINT_DATA="G0AbYQEbRQF0ZXN0c2Zhc2RmChtFAERhaWx5IFNlcnZpY2FzZGYKLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tChtFAU5FV0xPQzIKG0UALS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tChthABtFAU9yZGVyICMxNQobRQBUaW1lOiA4LzIxLzIwMjUsIDExOjEzOjEwIFBNCkNsaWVudDogbWFhcnRlbgotLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0KG0UBM3ggdGVzdGluZyAxChtFAAotLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0KCgoKCgoKCgoKCh1WAA=="

PRINTER_IP="192.168.1.100"
PRINTER_PORT="9100"

echo "Test 1: Direct printf of known working ESC/POS"
echo "------------------------------------------------"
printf '\x1b\x40\x1b\x45\x01BOLD TEST\x1b\x45\x00\nNormal text\n\n\n\x1d\x56\x00' | nc $PRINTER_IP $PRINTER_PORT
if [ $? -eq 0 ]; then
    echo "✓ Direct printf sent successfully"
    echo "  Should print: 'BOLD TEST' in bold, then 'Normal text'"
else
    echo "✗ Failed to send"
fi

sleep 2

echo ""
echo "Test 2: Decode to file and examine"
echo "-----------------------------------"
# Decode to binary file
echo "$PRINT_DATA" | base64 -d > /tmp/test.bin 2>/dev/null || echo "$PRINT_DATA" | base64 > /tmp/test.bin

# Check file size
SIZE=$(wc -c < /tmp/test.bin 2>/dev/null || echo 0)
echo "Decoded size: $SIZE bytes (expected: 346)"

# Show hex of first 20 bytes
if command -v hexdump >/dev/null 2>&1; then
    echo "First 20 bytes (hex):"
    hexdump -C -n 20 /tmp/test.bin
elif command -v od >/dev/null 2>&1; then
    echo "First 20 bytes (hex):"
    od -An -tx1 -N 20 /tmp/test.bin
fi

echo ""
echo "Test 3: Send decoded file to printer"
echo "-------------------------------------"
if [ -f /tmp/test.bin ] && [ "$SIZE" -gt 0 ]; then
    cat /tmp/test.bin | nc $PRINTER_IP $PRINTER_PORT
    if [ $? -eq 0 ]; then
        echo "✓ Sent decoded binary file"
    else
        echo "✗ Failed to send"
    fi
else
    echo "✗ No valid binary file to send"
fi

sleep 2

echo ""
echo "Test 4: Send with xxd if available"
echo "-----------------------------------"
if command -v xxd >/dev/null 2>&1; then
    # Create hex representation and convert back
    echo "$PRINT_DATA" | base64 -d | xxd -p > /tmp/test.hex
    xxd -r -p /tmp/test.hex | nc $PRINTER_IP $PRINTER_PORT
    if [ $? -eq 0 ]; then
        echo "✓ Sent via xxd conversion"
    else
        echo "✗ Failed to send"
    fi
else
    echo "✗ xxd not available"
fi

echo ""
echo "Test 5: Python binary send"
echo "---------------------------"
if command -v python3 >/dev/null 2>&1; then
    python3 << 'EOF'
import socket
import base64

print_data = "G0AbYQEbRQF0ZXN0c2Zhc2RmChtFAERhaWx5IFNlcnZpY2FzZGYKLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tChtFAU5FV0xPQzIKG0UALS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tChthABtFAU9yZGVyICMxNQobRQBUaW1lOiA4LzIxLzIwMDUsIDExOjEzOjEwIFBNCkNsaWVudDogbWFhcnRlbgotLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0KG0UBM3ggdGVzdGluZyAxChtFAAotLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0KCgoKCgoKCgoKCh1WAA=="

try:
    # Decode base64
    binary_data = base64.b64decode(print_data)
    
    # Send to printer
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(5)
    s.connect(("192.168.1.100", 9100))
    s.send(binary_data)
    s.close()
    print("✓ Sent via Python socket")
except Exception as e:
    print("✗ Python send failed:", str(e))
EOF
elif command -v python >/dev/null 2>&1; then
    python << 'EOF'
import socket
import base64

print_data = "G0AbYQEbRQF0ZXN0c2Zhc2RmChtFAERhaWx5IFNlcnZpY2FzZGYKLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tChtFAU5FV0xPQzIKG0UALS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tChthABtFAU9yZGVyICMxNQobRQBUaW1lOiA4LzIxLzIwMjUsIDExOjEzOjEwIFBNCkNsaWVudDogbWFhcnRlbgotLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0KG0UBM3ggdGVzdGluZyAxChtFAAotLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0KCgoKCgoKCgoKCh1WAA=="

try:
    # Decode base64
    binary_data = base64.b64decode(print_data)
    
    # Send to printer
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(5)
    s.connect(("192.168.1.100", 9100))
    s.send(binary_data)
    s.close()
    print("✓ Sent via Python socket")
except Exception as e:
    print("✗ Python send failed:", str(e))
EOF
else
    echo "✗ Python not available"
fi

echo ""
echo "Test 6: Compare binary files"
echo "-----------------------------"
# Create a known good file with printf
printf '\x1b\x40\x1b\x61\x01\x1b\x45\x01testsfasdf\n\x1b\x45\x00Daily Servicasdf\n' > /tmp/good.bin

echo "Known good file size: $(wc -c < /tmp/good.bin) bytes"
echo "Decoded file size: $(wc -c < /tmp/test.bin) bytes"

if command -v cmp >/dev/null 2>&1; then
    cmp -l /tmp/good.bin /tmp/test.bin 2>/dev/null | head -5
fi

echo ""
echo "=== Debug Complete ==="
echo ""
echo "Check which tests printed correctly vs gibberish."
echo "This will help identify where the data corruption occurs."