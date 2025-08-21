#!/usr/bin/env python3
"""
Generate correct ESC/POS print_data for receipts
This shows what the Base64-encoded print_data should contain
"""

import base64

def generate_receipt_data(order):
    """Generate proper ESC/POS commands for a receipt"""
    
    # Build the receipt as bytes
    data = bytearray()
    
    # ESC/POS Commands
    ESC = 0x1B
    GS = 0x1D
    
    # Initialize printer (IMPORTANT - always start with this)
    data.extend([ESC, 0x40])  # ESC @ - Initialize printer
    
    # Header - Location name (centered, double height)
    if order.get('location'):
        data.extend([ESC, 0x61, 0x01])  # ESC a 1 - Center alignment
        data.extend([ESC, 0x21, 0x10])  # ESC ! 16 - Double height
        data.extend(order['location'].encode('utf-8'))
        data.append(0x0A)  # Line feed
        data.extend([ESC, 0x21, 0x00])  # ESC ! 0 - Normal size
        data.append(0x0A)  # Extra line
    
    # Order info (left aligned)
    data.extend([ESC, 0x61, 0x00])  # ESC a 0 - Left alignment
    
    # Order number
    order_text = f"Order #{order.get('order_number', order.get('id', 'N/A'))}"
    data.extend(order_text.encode('utf-8'))
    data.append(0x0A)
    
    # Time
    import datetime
    time_text = datetime.datetime.now().strftime("%m/%d/%Y %I:%M %p")
    data.extend(f"Time: {time_text}".encode('utf-8'))
    data.append(0x0A)
    
    # Customer
    if order.get('customer', {}).get('name'):
        data.extend(f"Customer: {order['customer']['name']}".encode('utf-8'))
        data.append(0x0A)
    
    # Separator line
    data.extend(b'-' * 32)
    data.append(0x0A)
    
    # Items
    for item in order.get('items', []):
        qty = item.get('quantity', 1)
        name = item.get('name', 'Unknown')
        price = item.get('price', 0)
        
        # Format: "2x Item Name         $10.00"
        line = f"{qty}x {name}"
        if price:
            price_str = f"${float(price):.2f}"
            # Pad to align prices on the right (32 char width)
            line = line[:24].ljust(24) + price_str.rjust(8)
        
        data.extend(line.encode('utf-8'))
        data.append(0x0A)
        
        # Add notes if present
        if item.get('notes'):
            data.extend(f"   Note: {item['notes']}".encode('utf-8'))
            data.append(0x0A)
    
    # Separator line
    data.extend(b'-' * 32)
    data.append(0x0A)
    
    # Total (bold)
    if order.get('total'):
        data.extend([ESC, 0x21, 0x08])  # ESC ! 8 - Bold
        total_line = "TOTAL:".ljust(24) + f"${float(order['total']):.2f}".rjust(8)
        data.extend(total_line.encode('utf-8'))
        data.append(0x0A)
        data.extend([ESC, 0x21, 0x00])  # ESC ! 0 - Normal
    
    # Footer
    data.append(0x0A)
    data.extend([ESC, 0x61, 0x01])  # Center alignment
    data.extend(b"Thank You!")
    data.append(0x0A)
    data.extend([ESC, 0x61, 0x00])  # Left alignment
    
    # Feed paper and cut
    data.extend([0x0A, 0x0A, 0x0A])  # 3 line feeds
    data.extend([GS, 0x56, 0x00])     # GS V 0 - Full cut
    
    return bytes(data)

# Example order
example_order = {
    "id": "16",
    "order_number": 11,
    "location": "NEWLOC2",
    "customer": {"name": "asdfasdf"},
    "items": [
        {"name": "testing 1", "quantity": 4, "price": "12.00"}
    ],
    "total": "48.00"
}

# Generate the correct print data
print_data_bytes = generate_receipt_data(example_order)

# Encode to Base64 for API
print_data_base64 = base64.b64encode(print_data_bytes).decode('utf-8')

print("=" * 50)
print("CORRECT PRINT_DATA GENERATION")
print("=" * 50)
print("\n1. Base64 encoded print_data to send in API:")
print("-" * 40)
print(print_data_base64)

print("\n2. Hex dump of raw ESC/POS commands:")
print("-" * 40)
for i in range(0, min(len(print_data_bytes), 256), 16):
    hex_str = ' '.join(f'{b:02x}' for b in print_data_bytes[i:i+16])
    ascii_str = ''.join(chr(b) if 32 <= b < 127 else '.' for b in print_data_bytes[i:i+16])
    print(f"{i:08x}  {hex_str:<48}  |{ascii_str}|")

print("\n3. Human-readable content:")
print("-" * 40)
readable = []
for b in print_data_bytes:
    if b == 0x0A:
        readable.append('\n')
    elif 32 <= b < 127:
        readable.append(chr(b))
print(''.join(readable))

print("\n4. Key ESC/POS commands used:")
print("-" * 40)
print("• ESC @ (1B 40)     - Initialize printer")
print("• ESC a n (1B 61 n) - Text alignment (0=left, 1=center)")
print("• ESC ! n (1B 21 n) - Print mode (8=bold, 16=double height)")
print("• GS V 0 (1D 56 00) - Cut paper")
print("• LF (0A)           - Line feed")

print("\n5. Important notes:")
print("-" * 40)
print("• Always start with ESC @ (1B 40) to initialize")
print("• Avoid ESC t (1B 74) character code page commands")
print("• Use simple ASCII text for maximum compatibility")
print("• Test with your specific printer model")