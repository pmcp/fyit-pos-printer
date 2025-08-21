#!/bin/sh
# Test if TM-m30 supports ESC E for bold

PRINTER_IP="192.168.1.100"
PRINTER_PORT="9100"

echo "Testing ESC E commands on TM-m30"

# Test 1: With ESC E
echo "Test 1: ESC E for bold"
(printf '\x1b\x40'; printf '\x1b\x45\x01'; echo "BOLD TEXT"; printf '\x1b\x45\x00'; echo "Normal text"; printf '\n\n\n') | nc $PRINTER_IP $PRINTER_PORT
sleep 2

# Test 2: Without any formatting
echo "Test 2: Plain text only"
(printf '\x1b\x40'; echo "PLAIN TEXT TEST"; echo "No formatting"; printf '\n\n\n') | nc $PRINTER_IP $PRINTER_PORT
sleep 2

# Test 3: Try ESC - for underline instead
echo "Test 3: ESC - for underline"
(printf '\x1b\x40'; printf '\x1b\x2d\x01'; echo "UNDERLINE TEXT"; printf '\x1b\x2d\x00'; echo "Normal text"; printf '\n\n\n') | nc $PRINTER_IP $PRINTER_PORT

echo "Check what printed"