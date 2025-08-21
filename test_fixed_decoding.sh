#!/bin/sh
# Test script to verify the fixed Base64 decoding works correctly

echo "=== Testing Fixed Base64 Decoding ==="
echo ""

# The print data from the user
PRINT_DATA="G0AbYQEbRQF0ZXN0c2Zhc2RmChtFAERhaWx5IFNlcnZpY2FzZGYKLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tChtFAU5FV0xPQzIKG0UALS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tChthABtFAU9yZGVyICMxNQobRQBUaW1lOiA4LzIxLzIwMjUsIDExOjEzOjEwIFBNCkNsaWVudDogbWFhcnRlbgotLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0KG0UBM3ggdGVzdGluZyAxChtFAAotLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0KCgoKCgoKCgoKCh1WAA=="

OUTPUT_FILE="/tmp/test_decoded.bin"

echo "Test 1: Standard base64 command"
echo "--------------------------------"
if command -v base64 >/dev/null 2>&1; then
    # Try with -d flag
    if echo "$PRINT_DATA" | base64 -d > "$OUTPUT_FILE" 2>/dev/null; then
        echo "✓ Decoded with base64 -d"
        if [ -f "$OUTPUT_FILE" ]; then
            SIZE=$(wc -c < "$OUTPUT_FILE")
            echo "  File size: $SIZE bytes"
            
            # Check first bytes
            if command -v od >/dev/null 2>&1; then
                FIRST_BYTES=$(od -An -tx1 -N 2 "$OUTPUT_FILE" | tr -d ' ')
                if [ "$FIRST_BYTES" = "1b40" ]; then
                    echo "  ✓ Valid ESC/POS header (1B 40)"
                else
                    echo "  ✗ Invalid header: $FIRST_BYTES"
                fi
            fi
        fi
    else
        # Try without -d flag (BusyBox)
        if echo "$PRINT_DATA" | base64 > "$OUTPUT_FILE" 2>/dev/null; then
            echo "✓ Decoded with base64 (BusyBox mode)"
            SIZE=$(wc -c < "$OUTPUT_FILE")
            echo "  File size: $SIZE bytes"
        else
            echo "✗ base64 command failed"
        fi
    fi
else
    echo "✗ base64 command not found"
fi

echo ""
echo "Test 2: Python decoder"
echo "----------------------"
if command -v python3 >/dev/null 2>&1; then
    if echo "$PRINT_DATA" | python3 -c "import base64,sys; sys.stdout.buffer.write(base64.b64decode(sys.stdin.read()))" > "$OUTPUT_FILE" 2>/dev/null; then
        echo "✓ Decoded with python3"
        SIZE=$(wc -c < "$OUTPUT_FILE")
        echo "  File size: $SIZE bytes"
    else
        echo "✗ python3 decoding failed"
    fi
elif command -v python >/dev/null 2>&1; then
    if echo "$PRINT_DATA" | python -c "import base64,sys; sys.stdout.write(base64.b64decode(sys.stdin.read()))" > "$OUTPUT_FILE" 2>/dev/null; then
        echo "✓ Decoded with python"
        SIZE=$(wc -c < "$OUTPUT_FILE")
        echo "  File size: $SIZE bytes"
    else
        echo "✗ python decoding failed"
    fi
else
    echo "✗ Python not found"
fi

echo ""
echo "Test 3: Using helper script"
echo "---------------------------"
if [ -f "base64_decoder.py" ]; then
    if echo "$PRINT_DATA" | python base64_decoder.py > "$OUTPUT_FILE" 2>/dev/null; then
        echo "✓ Decoded with base64_decoder.py"
        SIZE=$(wc -c < "$OUTPUT_FILE")
        echo "  File size: $SIZE bytes"
    else
        echo "✗ Helper script failed"
    fi
else
    echo "✗ Helper script not found"
fi

echo ""
echo "Test 4: Binary safety with dd"
echo "------------------------------"
if [ -f "$OUTPUT_FILE" ] && command -v dd >/dev/null 2>&1; then
    COPY_FILE="/tmp/test_dd_copy.bin"
    dd if="$OUTPUT_FILE" of="$COPY_FILE" bs=1 2>/dev/null
    if [ $? -eq 0 ]; then
        echo "✓ dd can read/write the binary file"
        ORIG_SIZE=$(wc -c < "$OUTPUT_FILE")
        COPY_SIZE=$(wc -c < "$COPY_FILE")
        if [ "$ORIG_SIZE" = "$COPY_SIZE" ]; then
            echo "  ✓ File sizes match: $ORIG_SIZE bytes"
        else
            echo "  ✗ Size mismatch: orig=$ORIG_SIZE, copy=$COPY_SIZE"
        fi
    else
        echo "✗ dd failed"
    fi
else
    echo "✗ dd not available or no decoded file"
fi

echo ""
echo "Test 5: Simulated printer send (to /dev/null)"
echo "-----------------------------------------------"
if [ -f "$OUTPUT_FILE" ]; then
    # Test with dd + nc simulation
    if command -v dd >/dev/null 2>&1; then
        dd if="$OUTPUT_FILE" bs=1 2>/dev/null | cat > /dev/null
        if [ $? -eq 0 ]; then
            echo "✓ dd + pipe works"
        else
            echo "✗ dd + pipe failed"
        fi
    fi
    
    # Test with cat
    cat "$OUTPUT_FILE" > /dev/null
    if [ $? -eq 0 ]; then
        echo "✓ cat works"
    else
        echo "✗ cat failed"
    fi
else
    echo "✗ No decoded file to test"
fi

echo ""
echo "=== Test Complete ==="
echo ""
echo "Expected decoded size: 346 bytes"
echo "Expected first bytes: 1B 40 (ESC @)"
echo ""

if [ -f "$OUTPUT_FILE" ]; then
    echo "Decoded file saved at: $OUTPUT_FILE"
    echo "You can inspect it with:"
    echo "  od -An -tx1 -N 20 $OUTPUT_FILE"
    echo "  hexdump -C -n 50 $OUTPUT_FILE"
fi