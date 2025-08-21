#!/usr/bin/env python3
"""
Mock FriendlyPOS API Server for Testing
"""

import json
import http.server
import socketserver
import threading
import time
from datetime import datetime
import argparse
import random


class MockAPIHandler(http.server.BaseHTTPRequestHandler):
    """Handle mock API requests"""
    
    orders_queue = []
    orders_processed = []
    order_counter = 1
    
    def do_GET(self):
        """Handle GET requests"""
        if self.path.startswith('/api/print-queue'):
            self.handle_print_queue()
        elif self.path == '/api/printers':
            self.handle_printers()
        elif self.path == '/api/settings':
            self.handle_settings()
        else:
            self.send_error(404, "Endpoint not found")
    
    def do_PATCH(self):
        """Handle PATCH requests"""
        if '/api/orders/' in self.path and '/status' in self.path:
            self.handle_order_status_update()
        else:
            self.send_error(404, "Endpoint not found")
    
    def do_POST(self):
        """Handle POST requests"""
        if self.path == '/api/test/create-order':
            self.handle_create_test_order()
        else:
            self.send_error(404, "Endpoint not found")
    
    def handle_print_queue(self):
        """Return pending print jobs"""
        location_id = self.get_query_param('location_id')
        
        if not self.check_api_key():
            return
        
        pending_orders = [o for o in self.orders_queue if not o.get('printed')]
        
        if location_id:
            pending_orders = [o for o in pending_orders if o.get('location_id') == location_id]
        
        self.send_json_response(pending_orders)
        
        if self.server.verbose:
            print(f"[API] GET /api/print-queue - Returned {len(pending_orders)} orders")
    
    def handle_printers(self):
        """Return printer configurations"""
        if not self.check_api_key():
            return
        
        printers = [
            {
                'id': 1,
                'name': 'main',
                'host': '127.0.0.1',
                'port': 9101,
                'location_id': '1',
                'type': 'receipt'
            },
            {
                'id': 2,
                'name': 'kitchen',
                'host': '127.0.0.1',
                'port': 9102,
                'location_id': '1',
                'type': 'kitchen'
            }
        ]
        
        self.send_json_response(printers)
        
        if self.server.verbose:
            print(f"[API] GET /api/printers - Returned {len(printers)} printers")
    
    def handle_settings(self):
        """Return event settings"""
        if not self.check_api_key():
            return
        
        settings = {
            'event_name': 'Test Event',
            'header': 'MOCK CAFE',
            'footer': 'Thank you for your order!',
            'currency': 'USD',
            'tax_rate': 0.08,
            'print_customer_copy': True
        }
        
        self.send_json_response(settings)
        
        if self.server.verbose:
            print("[API] GET /api/settings - Returned event settings")
    
    def handle_order_status_update(self):
        """Update order status"""
        if not self.check_api_key():
            return
        
        order_id = self.path.split('/')[3]
        
        content_length = int(self.headers.get('Content-Length', 0))
        body = self.rfile.read(content_length)
        data = json.loads(body) if body else {}
        
        for order in self.orders_queue:
            if str(order['id']) == order_id:
                order['status'] = data.get('status', order.get('status'))
                order['printed'] = data.get('status') == 'printed'
                order['printed_at'] = data.get('printed_at')
                
                if order['printed']:
                    self.orders_processed.append(order)
                
                self.send_json_response({'success': True, 'order': order})
                
                if self.server.verbose:
                    print(f"[API] PATCH /api/orders/{order_id}/status - Updated to {data.get('status')}")
                return
        
        self.send_error(404, f"Order {order_id} not found")
    
    def handle_create_test_order(self):
        """Create a test order (for testing purposes)"""
        content_length = int(self.headers.get('Content-Length', 0))
        body = self.rfile.read(content_length) if content_length else b'{}'
        data = json.loads(body)
        
        order = self.create_sample_order(
            order_type=data.get('type', 'random'),
            location_id=data.get('location_id', '1')
        )
        
        self.orders_queue.append(order)
        self.send_json_response(order)
        
        if self.server.verbose:
            print(f"[API] POST /api/test/create-order - Created order #{order['id']}")
    
    def create_sample_order(self, order_type='random', location_id='1'):
        """Generate a sample order"""
        order_types = {
            'simple': {
                'items': [
                    {'quantity': 1, 'name': 'Coffee', 'price': 3.50}
                ],
                'customer': {'name': 'Test Customer'}
            },
            'complex': {
                'items': [
                    {'quantity': 2, 'name': 'Burger', 'price': 12.50, 'notes': 'No onions'},
                    {'quantity': 1, 'name': 'Fries', 'price': 4.50},
                    {'quantity': 2, 'name': 'Soda', 'price': 2.50}
                ],
                'customer': {'name': 'John Doe', 'phone': '555-1234'},
                'notes': 'Table 5'
            },
            'kitchen': {
                'items': [
                    {'quantity': 1, 'name': 'Pizza Margherita', 'price': 15.00, 'notes': 'Extra cheese'},
                    {'quantity': 1, 'name': 'Caesar Salad', 'price': 8.00}
                ],
                'printer': 'kitchen',
                'customer': {'name': 'Kitchen Order'}
            }
        }
        
        if order_type == 'random':
            order_type = random.choice(list(order_types.keys()))
        
        template = order_types.get(order_type, order_types['simple'])
        
        order = {
            'id': str(MockAPIHandler.order_counter),
            'location_id': location_id,
            'status': 'pending',
            'printed': False,
            'created_at': datetime.now().isoformat(),
            **template
        }
        
        total = sum(item['quantity'] * item['price'] for item in order['items'])
        order['total'] = round(total, 2)
        
        MockAPIHandler.order_counter += 1
        
        return order
    
    def check_api_key(self):
        """Verify API key"""
        api_key = self.headers.get('X-API-Key')
        
        if self.server.require_auth and api_key != 'test-api-key':
            self.send_error(401, "Invalid API key")
            return False
        
        return True
    
    def get_query_param(self, param):
        """Extract query parameter from URL"""
        if '?' in self.path:
            query_string = self.path.split('?')[1]
            params = dict(p.split('=') for p in query_string.split('&') if '=' in p)
            return params.get(param)
        return None
    
    def send_json_response(self, data):
        """Send JSON response"""
        response = json.dumps(data).encode('utf-8')
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(response)))
        self.end_headers()
        self.wfile.write(response)
    
    def log_message(self, format, *args):
        """Override to control logging"""
        if self.server.verbose:
            super().log_message(format, *args)


class MockAPIServer:
    """Mock API server for testing"""
    
    def __init__(self, host='0.0.0.0', port=8080, verbose=True, require_auth=True):
        self.host = host
        self.port = port
        self.verbose = verbose
        self.require_auth = require_auth
        self.server = None
        self.thread = None
    
    def start(self):
        """Start the mock API server"""
        handler = MockAPIHandler
        self.server = socketserver.TCPServer((self.host, self.port), handler)
        self.server.verbose = self.verbose
        self.server.require_auth = self.require_auth
        
        self.thread = threading.Thread(target=self.server.serve_forever)
        self.thread.daemon = True
        self.thread.start()
        
        print(f"Mock API Server Started")
        print(f"URL: http://{self.host}:{self.port}")
        print(f"Auth Required: {self.require_auth}")
        if self.require_auth:
            print(f"API Key: test-api-key")
        print("")
        print("Endpoints:")
        print(f"  GET  /api/print-queue?location_id=1")
        print(f"  GET  /api/printers")
        print(f"  GET  /api/settings")
        print(f"  PATCH /api/orders/:id/status")
        print(f"  POST /api/test/create-order")
        print("")
    
    def stop(self):
        """Stop the mock API server"""
        if self.server:
            self.server.shutdown()
            self.thread.join(timeout=5)
        print("Mock API Server Stopped")
    
    def create_test_orders(self, count=3):
        """Pre-populate with test orders"""
        for i in range(count):
            order = MockAPIHandler().create_sample_order()
            MockAPIHandler.orders_queue.append(order)
        print(f"Created {count} test orders")


def main():
    parser = argparse.ArgumentParser(description='Mock FriendlyPOS API Server')
    parser.add_argument('--host', default='127.0.0.1', help='Host to bind to')
    parser.add_argument('--port', type=int, default=8080, help='Port to listen on')
    parser.add_argument('--no-auth', action='store_true', help='Disable API key requirement')
    parser.add_argument('--quiet', action='store_true', help='Reduce verbosity')
    parser.add_argument('--orders', type=int, default=3, help='Number of test orders to create')
    
    args = parser.parse_args()
    
    server = MockAPIServer(
        host=args.host,
        port=args.port,
        verbose=not args.quiet,
        require_auth=not args.no_auth
    )
    
    try:
        server.start()
        
        if args.orders > 0:
            server.create_test_orders(args.orders)
        
        print("Press Ctrl+C to stop")
        while True:
            time.sleep(1)
            
    except KeyboardInterrupt:
        print("\nShutting down...")
        server.stop()


if __name__ == '__main__':
    main()