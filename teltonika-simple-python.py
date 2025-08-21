#!/usr/bin/env python
"""
Simple Python print server for Teltonika - bypasses shell binary issues
Minimal dependencies, works with Python 2 or 3
"""

import sys
import socket
import time
import base64
import json

# Python 2/3 compatibility
if sys.version_info[0] >= 3:
    import urllib.request as urllib2
    import urllib.error
else:
    import urllib2

API_URL = "https://friendlypos.vercel.app/api/print-queue"
API_KEY = "d5a8262b7cfd8f46e599b36c584bb1ec16f28436680ddaa53f700e6d8a1765fa"
POLL_INTERVAL = 2

def log(msg):
    """Simple logging"""
    timestamp = time.strftime("%Y-%m-%d %H:%M:%S")
    print("[%s] %s" % (timestamp, msg))
    sys.stdout.flush()

def fetch_orders():
    """Fetch pending orders from API"""
    try:
        req = urllib2.Request(API_URL)
        req.add_header('X-API-Key', API_KEY)
        
        # Disable SSL verification for Vercel
        import ssl
        ctx = ssl.create_default_context()
        ctx.check_hostname = False
        ctx.verify_mode = ssl.CERT_NONE
        
        response = urllib2.urlopen(req, context=ctx)
        data = response.read()
        
        if sys.version_info[0] >= 3:
            data = data.decode('utf-8')
        
        return json.loads(data)
    except Exception as e:
        log("ERROR: Failed to fetch orders: %s" % str(e))
        return []

def send_to_printer(binary_data, printer_ip, printer_port=9100):
    """Send binary data directly to printer via socket"""
    try:
        # Create socket
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.settimeout(5.0)
        
        # Connect to printer
        s.connect((printer_ip, printer_port))
        
        # Send binary data
        s.send(binary_data)
        
        # Close connection
        s.close()
        
        return True
    except Exception as e:
        log("ERROR: Failed to send to printer: %s" % str(e))
        return False

def mark_complete(order_id):
    """Mark order as complete"""
    try:
        url = "https://friendlypos.vercel.app/api/print-queue/%s/complete" % order_id
        req = urllib2.Request(url, data=b'', method='POST')
        req.add_header('X-API-Key', API_KEY)
        
        import ssl
        ctx = ssl.create_default_context()
        ctx.check_hostname = False
        ctx.verify_mode = ssl.CERT_NONE
        
        urllib2.urlopen(req, context=ctx)
        log("Order %s marked as complete" % order_id)
    except Exception as e:
        log("ERROR: Failed to mark order complete: %s" % str(e))

def mark_failed(order_id, error_msg):
    """Mark order as failed"""
    try:
        url = "https://friendlypos.vercel.app/api/print-queue/%s/fail" % order_id
        data = json.dumps({"error": error_msg})
        if sys.version_info[0] >= 3:
            data = data.encode('utf-8')
        
        req = urllib2.Request(url, data=data, method='POST')
        req.add_header('X-API-Key', API_KEY)
        req.add_header('Content-Type', 'application/json')
        
        import ssl
        ctx = ssl.create_default_context()
        ctx.check_hostname = False
        ctx.verify_mode = ssl.CERT_NONE
        
        urllib2.urlopen(req, context=ctx)
        log("Order %s marked as failed: %s" % (order_id, error_msg))
    except Exception as e:
        log("ERROR: Failed to mark order failed: %s" % str(e))

def process_order(order):
    """Process a single order"""
    order_id = order.get('id') or order.get('queue_id')
    if not order_id:
        log("WARNING: No order ID found")
        return
    
    printer_ip = order.get('printer_ip') or order.get('ip_address')
    if not printer_ip:
        log("WARNING: No printer IP for order %s" % order_id)
        return
    
    printer_port = order.get('port', order.get('printer_port', 9100))
    
    log("Processing order %s for printer %s:%s" % (order_id, printer_ip, printer_port))
    
    # Get print_data
    print_data = order.get('print_data')
    
    if print_data:
        try:
            # Decode base64 to binary
            binary_data = base64.b64decode(print_data)
            
            log("Decoded %d bytes of ESC/POS data" % len(binary_data))
            
            # Verify ESC/POS header
            if binary_data[:2] == b'\x1b\x40':
                log("Valid ESC/POS data (starts with ESC @)")
            
            # Send to printer
            if send_to_printer(binary_data, printer_ip, printer_port):
                log("Order %s printed successfully" % order_id)
                mark_complete(order_id)
            else:
                log("Failed to print order %s" % order_id)
                mark_failed(order_id, "Failed to send to printer")
                
        except Exception as e:
            log("ERROR: Failed to process print_data: %s" % str(e))
            mark_failed(order_id, "Failed to decode print data")
    else:
        log("No print_data for order %s - using fallback" % order_id)
        
        # Simple fallback
        order_num = order.get('order_number', order_id)
        
        # Build simple ESC/POS receipt
        receipt = b'\x1b\x40'  # Init
        receipt += b'\x1b\x61\x01'  # Center
        receipt += ('ORDER #%s\n' % order_num).encode('utf-8')
        receipt += b'\x1b\x61\x00'  # Left
        receipt += b'========================\n'
        
        # Add items if available
        items = order.get('items', [])
        for item in items:
            name = item.get('name', 'Unknown')
            receipt += ('- %s\n' % name).encode('utf-8')
        
        receipt += b'========================\n'
        receipt += time.strftime('%Y-%m-%d %H:%M:%S\n').encode('utf-8')
        receipt += b'\n\n\n\x1d\x56\x00'  # Feed and cut
        
        if send_to_printer(receipt, printer_ip, printer_port):
            log("Order %s printed (fallback mode)" % order_id)
            mark_complete(order_id)
        else:
            mark_failed(order_id, "Failed to print")

def main():
    """Main loop"""
    log("Python Print Server Started")
    log("API: %s" % API_URL)
    log("Poll interval: %d seconds" % POLL_INTERVAL)
    
    while True:
        try:
            orders = fetch_orders()
            
            if orders and isinstance(orders, list):
                log("Found %d order(s)" % len(orders))
                
                for order in orders:
                    process_order(order)
                    time.sleep(1)  # Small delay between orders
            
        except KeyboardInterrupt:
            log("Shutting down...")
            break
        except Exception as e:
            log("ERROR in main loop: %s" % str(e))
        
        time.sleep(POLL_INTERVAL)

if __name__ == "__main__":
    main()