#!/bin/sh
# Epson Thermal Printer Test Script
# Run this on the Teltonika to test different ESC/POS commands

PRINTER_IP="192.168.1.100"
PRINTER_PORT="9100"

echo "=== Epson Thermal Printer Tests ==="
echo "Testing printer at $PRINTER_IP:$PRINTER_PORT"
echo ""

# Test 1: Most basic print
echo "Test 1: Ultra simple (just text)"
echo "SIMPLE TEST 1" | nc $PRINTER_IP $PRINTER_PORT
sleep 2

# Test 2: With initialization only
echo "Test 2: With ESC @ init"
(printf '\x1b\x40'; echo "INIT TEST 2"; printf '\n\n\n') | nc $PRINTER_IP $PRINTER_PORT
sleep 2

# Test 3: With init and cut
echo "Test 3: With init and cut"
(printf '\x1b\x40'; echo "INIT AND CUT TEST 3"; printf '\n\n\n\x1d\x56\x00') | nc $PRINTER_IP $PRINTER_PORT
sleep 2

# Test 4: With alignment
echo "Test 4: With alignment"
(printf '\x1b\x40'; printf '\x1b\x61\x01'; echo "CENTER TEST 4"; printf '\x1b\x61\x00'; printf '\n\n\n\x1d\x56\x00') | nc $PRINTER_IP $PRINTER_PORT
sleep 2

# Test 5: With bold only (ESC E)
echo "Test 5: With bold (ESC E method)"
(printf '\x1b\x40'; printf '\x1b\x45\x01'; echo "BOLD TEST 5"; printf '\x1b\x45\x00'; echo "Normal text"; printf '\n\n\n\x1d\x56\x00') | nc $PRINTER_IP $PRINTER_PORT
sleep 2

# Test 6: With ESC ! 08 (bold)
echo "Test 6: With ESC ! bold"
(printf '\x1b\x40'; printf '\x1b\x21\x08'; echo "BOLD TEST 6"; printf '\x1b\x21\x00'; echo "Normal text"; printf '\n\n\n\x1d\x56\x00') | nc $PRINTER_IP $PRINTER_PORT
sleep 2

# Test 7: The problematic double height/width
echo "Test 7: Double height (might fail)"
(printf '\x1b\x40'; printf '\x1b\x21\x10'; echo "DOUBLE HEIGHT 7"; printf '\x1b\x21\x00'; printf '\n\n\n\x1d\x56\x00') | nc $PRINTER_IP $PRINTER_PORT
sleep 2

# Test 8: Feed commands
echo "Test 8: Different feed commands"
(printf '\x1b\x40'; echo "FEED TEST 8"; printf '\x1b\x64\x04'; printf '\x1d\x56\x00') | nc $PRINTER_IP $PRINTER_PORT
sleep 2

echo ""
echo "=== Tests complete ==="
echo "Check which tests printed correctly"