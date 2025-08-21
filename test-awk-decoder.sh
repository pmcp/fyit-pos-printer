#!/bin/sh
# Test AWK Base64 decoder on Teltonika

echo "Testing AWK Base64 decoder..."

# The print data from user
PRINT_DATA="G0AbYQEbRQF0ZXN0c2Zhc2RmChtFAERhaWx5IFNlcnZpY2FzZGYKLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tChtFAU5FV0xPQzIKG0UALS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tChthABtFAU9yZGVyICMxNQobRQBUaW1lOiA4LzIxLzIwMjUsIDExOjEzOjEwIFBNCkNsaWVudDogbWFhcnRlbgotLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0KG0UBM3ggdGVzdGluZyAxChtFAAotLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0KCgoKCgoKCgoKCh1WAA=="

# AWK decoder function
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

echo ""
echo "Test 1: Decode to file and check size"
echo "--------------------------------------"
echo "$PRINT_DATA" | decode_base64_awk > /tmp/awk_decoded.bin
SIZE=$(wc -c < /tmp/awk_decoded.bin)
echo "Decoded size: $SIZE bytes (expected: 346)"

echo ""
echo "Test 2: Check first bytes with od"
echo "----------------------------------"
if command -v od >/dev/null 2>&1; then
    echo "First 20 bytes (hex):"
    od -An -tx1 -N 20 /tmp/awk_decoded.bin
    
    # Check for ESC @ 
    FIRST_BYTES=$(od -An -tx1 -N 2 /tmp/awk_decoded.bin | tr -d ' ')
    if [ "$FIRST_BYTES" = "1b40" ]; then
        echo "✓ Valid ESC/POS header (1B 40)"
    else
        echo "✗ Invalid header: $FIRST_BYTES"
    fi
fi

echo ""
echo "Test 3: Send to printer"
echo "------------------------"
PRINTER_IP="192.168.1.100"
cat /tmp/awk_decoded.bin | nc $PRINTER_IP 9100
if [ $? -eq 0 ]; then
    echo "✓ Sent decoded data to printer"
else
    echo "✗ Failed to send"
fi

echo ""
echo "Test 4: Direct pipeline (no temp file)"
echo "---------------------------------------"
echo "$PRINT_DATA" | decode_base64_awk | nc $PRINTER_IP 9100
if [ $? -eq 0 ]; then
    echo "✓ Direct pipeline to printer worked"
else
    echo "✗ Direct pipeline failed"
fi

echo ""
echo "=== Test Complete ==="
echo "Check if the printer output is correct or gibberish"