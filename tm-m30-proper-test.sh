#!/bin/sh
# Test proper TM-m30 initialization and formatting

PRINTER_IP="192.168.1.100"
PRINTER_PORT="9100"

echo "=== TM-m30 Proper Test ==="

# Test 1: Epson recommended initialization for TM-m30
echo "Test 1: Full TM-m30 init"
{
    printf '\x1b\x40'        # ESC @ - Initialize
    printf '\x1b\x74\x00'    # ESC t 0 - Code page 0 (CP437)
    printf '\x1b\x52\x00'    # ESC R 0 - International character set USA
    printf 'AFTER FULL INIT\n'
    printf '\x1b\x45\x01'    # ESC E 1 - Bold on
    printf 'BOLD TEXT\n'
    printf '\x1b\x45\x00'    # ESC E 0 - Bold off
    printf 'Normal text\n'
    printf '\n\n\n'
    printf '\x1d\x56\x00'    # Cut
} | nc $PRINTER_IP $PRINTER_PORT
sleep 3

# Test 2: Try GS ! for character size (TM-m30 specific)
echo "Test 2: GS ! for size"
{
    printf '\x1b\x40'        # Initialize
    printf '\x1d\x21\x11'    # GS ! - Double width and height
    printf 'DOUBLE SIZE\n'
    printf '\x1d\x21\x00'    # GS ! - Normal
    printf 'Normal size\n'
    printf '\n\n\n'
    printf '\x1d\x56\x00'    # Cut
} | nc $PRINTER_IP $PRINTER_PORT
sleep 3

# Test 3: Simple bold without any code page
echo "Test 3: Simple bold"
{
    printf '\x1b\x40'        # Initialize only
    printf '\x1b\x45\x01'    # Bold on
    printf 'SIMPLE BOLD\n'
    printf '\x1b\x45\x00'    # Bold off
    printf 'Simple normal\n'
    printf '\n\n\n'
} | nc $PRINTER_IP $PRINTER_PORT

echo "Check which test worked correctly"