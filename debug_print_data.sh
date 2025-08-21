#!/bin/sh
# Debug script to see what's actually in the print_data

SAMPLE_DATA="G3QSG2EBGyEQGyEgdGVzdHNmYXNkZgobIQBEYWlseSBTZXJ2aWNhc2RmCi0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLQobIRAbISBORVdMT0MyChshAC0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLQobYQAbIRBPcmRlciAjMTEKGyEAVGltZTogOC8yMS8yMDI1LCA5OjQxOjU4IFBNCkNsaWVudDogYXNkZmFzZGYKLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tChshEBshIDR4IHRlc3RpbmcgMQobIQAKLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tCgoKG2QEG2QEHVYAG0A="

echo "=== Decoding print_data ==="
echo "$SAMPLE_DATA" | base64 -d > /tmp/decoded.bin

echo "=== Hex dump of decoded data ==="
hexdump -C /tmp/decoded.bin | head -20

echo ""
echo "=== Raw text (visible characters only) ==="
strings /tmp/decoded.bin

echo ""
echo "=== Checking for ESC/POS commands ==="
if hexdump -C /tmp/decoded.bin | grep -q "1b 40"; then
    echo "✓ Found ESC @ (Initialize printer)"
fi
if hexdump -C /tmp/decoded.bin | grep -q "1b 61"; then
    echo "✓ Found ESC a (Alignment)"
fi
if hexdump -C /tmp/decoded.bin | grep -q "1b 21"; then
    echo "✓ Found ESC ! (Print mode)"
fi
if hexdump -C /tmp/decoded.bin | grep -q "1d 56"; then
    echo "✓ Found GS V (Cut paper)"
fi

echo ""
echo "=== Testing simple ESC/POS print ==="
echo "Creating a simple test receipt..."
(
    printf '\x1b\x40'           # Initialize
    printf '\x1b\x61\x01'        # Center align
    printf 'TEST RECEIPT\n'
    printf '\x1b\x61\x00'        # Left align
    printf '====================\n'
    printf 'Item 1 .........$10.00\n'
    printf 'Item 2 .........$15.00\n'
    printf '====================\n'
    printf 'TOTAL         $25.00\n'
    printf '\n\n\n'
    printf '\x1d\x56\x00'        # Cut
) > /tmp/test_receipt.bin

echo "Hex dump of test receipt:"
hexdump -C /tmp/test_receipt.bin | head -10