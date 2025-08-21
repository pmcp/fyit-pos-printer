#!/bin/sh
# Direct printer tests to diagnose the issue

PRINTER_IP="192.168.1.100"
PRINTER_PORT="9100"

echo "=== Direct Printer Tests ==="

# Test 1: ASCII text only
echo "Test 1: Pure ASCII"
echo "ABCDEFGHIJKLMNOPQRSTUVWXYZ" | nc $PRINTER_IP $PRINTER_PORT
sleep 2

# Test 2: Numbers
echo "Test 2: Numbers"
echo "0123456789" | nc $PRINTER_IP $PRINTER_PORT
sleep 2

# Test 3: With newlines
echo "Test 3: Multiple lines"
(echo "LINE 1"; echo "LINE 2"; echo "LINE 3") | nc $PRINTER_IP $PRINTER_PORT
sleep 2

# Test 4: Raw hex for "HELLO"
echo "Test 4: Raw hex for HELLO"
printf '\x48\x45\x4C\x4C\x4F\x0A' | nc $PRINTER_IP $PRINTER_PORT
sleep 2

# Test 5: Check if printer is in hex dump mode
echo "Test 5: Reset and test"
printf '\x1B\x40RESET TEST\x0A' | nc $PRINTER_IP $PRINTER_PORT
sleep 2

echo "Tests complete - check what printed"