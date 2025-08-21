#!/usr/bin/env python
"""
Simple Base64 decoder helper for Teltonika print server
Uses only Python standard library - no external dependencies
"""

import sys
import base64

def decode_base64_to_binary(input_data):
    """Decode base64 string to binary data"""
    try:
        # Remove any whitespace
        input_data = input_data.strip()
        
        # Decode base64
        binary_data = base64.b64decode(input_data)
        
        # Write binary data to stdout
        if sys.version_info[0] >= 3:
            sys.stdout.buffer.write(binary_data)
        else:
            sys.stdout.write(binary_data)
            
        return True
    except Exception as e:
        sys.stderr.write("Error decoding base64: %s\n" % str(e))
        return False

if __name__ == "__main__":
    # Read base64 data from stdin
    input_data = sys.stdin.read()
    
    if not decode_base64_to_binary(input_data):
        sys.exit(1)