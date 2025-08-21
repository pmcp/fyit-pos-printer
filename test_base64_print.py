#!/usr/bin/env python3
"""
Test script to verify base64 print data handling
"""

import base64
import json

# Sample print_data from your logs
sample_print_data = "G3QSG2EBGyEQGyEgdGVzdHNmYXNkZgobIQBEYWlseSBTZXJ2aWNhc2RmCi0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLQobIRAbISBORVdMT0MyChshAC0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLQobYQAbIRBPcmRlciAjMTEKGyEAVGltZTogOC8yMS8yMDI1LCA5OjQxOjU4IFBNCkNsaWVudDogYXNkZmFzZGYKLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tChshEBshIDR4IHRlc3RpbmcgMQobIQAKLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tCgoKG2QEG2QEHVYAG0A="

try:
    # Decode the base64 data
    raw_data = base64.b64decode(sample_print_data)
    print("✓ Successfully decoded base64 print data")
    print(f"  Raw data length: {len(raw_data)} bytes")
    
    # Extract readable text (ignoring ESC/POS control codes)
    readable_text = []
    for byte in raw_data:
        if 32 <= byte <= 126:  # Printable ASCII range
            readable_text.append(chr(byte))
        elif byte == 10:  # Newline
            readable_text.append('\n')
    
    print("\n📄 Extracted text content:")
    print("-" * 40)
    print(''.join(readable_text))
    print("-" * 40)
    
    # Check for ESC/POS commands
    print("\n🔍 ESC/POS command detection:")
    if b'\x1b' in raw_data:
        print("  ✓ ESC commands found")
    if b'\x1d' in raw_data:
        print("  ✓ GS commands found")
    if b'\x1d\x56' in raw_data:
        print("  ✓ Paper cut command found")
        
except Exception as e:
    print(f"❌ Failed to decode print data: {e}")