#!/bin/sh
# TM-m30 specific tests

PRINTER_IP="192.168.1.100"
PRINTER_PORT="9100"

echo "=== TM-m30 Printer Tests ==="

# Test 1: Initialize and print with TM-m30 specific commands
echo "Test 1: TM-m30 init sequence"
(printf '\x1b\x40\x1b\x3d\x01'; echo "TM-M30 INIT TEST"; printf '\x1b\x64\x03\x1b\x69') | nc $PRINTER_IP $PRINTER_PORT
sleep 2

# Test 2: Check if printer needs GS a command (auto status back)
echo "Test 2: Disable auto status"
(printf '\x1d\x61\x00'; echo "STATUS DISABLED TEST"; printf '\n\n\n') | nc $PRINTER_IP $PRINTER_PORT
sleep 2

# Test 3: Simple text with minimal commands
echo "Test 3: Minimal commands"
(printf '\x1b\x40'; echo "MINIMAL TEST"; printf '\n\n\n\n\n') | nc $PRINTER_IP $PRINTER_PORT

echo "Tests complete"