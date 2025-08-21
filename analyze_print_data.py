#!/usr/bin/env python3
"""Analyze the Base64 print data to understand its structure"""

import base64
import sys

# The print data from the user
print_data = "G0AbYQEbRQF0ZXN0c2Zhc2RmChtFAERhaWx5IFNlcnZpY2FzZGYKLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tChtFAU5FV0xPQzIKG0UALS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tChthABtFAU9yZGVyICMxNQobRQBUaW1lOiA4LzIxLzIwMjUsIDExOjEzOjEwIFBNCkNsaWVudDogbWFhcnRlbgotLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0KG0UBM3ggdGVzdGluZyAxChtFAAotLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0KCgoKCgoKCgoKCh1WAA=="

try:
    # Decode the Base64 data
    raw_data = base64.b64decode(print_data)
    
    print("=== Base64 Print Data Analysis ===\n")
    print(f"Base64 length: {len(print_data)} characters")
    print(f"Decoded binary length: {len(raw_data)} bytes\n")
    
    # Show hex dump of first 50 bytes
    print("First 50 bytes (hex):")
    for i in range(min(50, len(raw_data))):
        if i % 16 == 0:
            print(f"\n{i:04x}: ", end="")
        print(f"{raw_data[i]:02x} ", end="")
    print("\n")
    
    # Check for ESC/POS commands
    print("\n=== ESC/POS Commands Found ===")
    
    if raw_data[:2] == b'\x1b\x40':
        print("✓ ESC @ (Initialize printer) at position 0")
    
    if b'\x1b\x61' in raw_data:
        print("✓ ESC a (Alignment) commands found")
        
    if b'\x1b\x45\x01' in raw_data:
        print("✓ ESC E 1 (Bold ON) commands found")
        
    if b'\x1b\x45\x00' in raw_data:
        print("✓ ESC E 0 (Bold OFF) commands found")
        
    if b'\x1d\x56\x00' in raw_data:
        print("✓ GS V 0 (Cut paper) command found")
    
    # Show the text content
    print("\n=== Readable Text Content ===")
    # Replace non-printable with dots except newlines
    text = ""
    for byte in raw_data:
        if byte == 0x0a:  # newline
            text += '\n'
        elif 32 <= byte < 127:  # printable ASCII
            text += chr(byte)
        else:
            text += '.'
    print(text)
    
    # Save the binary data to a file for testing
    with open('/Users/pmcp/Projects/fyit-pos-printer/test_print.bin', 'wb') as f:
        f.write(raw_data)
    print("\n✓ Binary data saved to test_print.bin")
    
except Exception as e:
    print(f"Error: {e}")
    sys.exit(1)