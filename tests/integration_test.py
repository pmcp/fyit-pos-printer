#!/usr/bin/env python3
"""
Integration test for FriendlyPOS Print Server
Tests the complete flow: API -> Print Server -> Printer
"""

import sys
import os
import time
import subprocess
import signal
import json
import urllib.request
import socket

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from tests.mock_api import MockAPIServer
from tests.mock_printer import MockPrinter


class IntegrationTest:
    """Run full integration test"""
    
    def __init__(self):
        self.api_server = None
        self.printer = None
        self.print_server_process = None
        self.test_passed = True
        
        self.api_port = 8080
        self.printer_port = 9101
    
    def setup(self):
        """Set up test environment"""
        print("=" * 60)
        print("FriendlyPOS Print Server - Integration Test")
        print("=" * 60)
        print()
        
        print("1. Starting Mock API Server...")
        self.api_server = MockAPIServer(
            host='127.0.0.1',
            port=self.api_port,
            verbose=False,
            require_auth=True
        )
        self.api_server.start()
        time.sleep(1)
        
        print("2. Starting Mock Printer...")
        self.printer = MockPrinter(
            host='127.0.0.1',
            port=self.printer_port,
            verbose=False,
            log_file='/tmp/integration_test_prints.log'
        )
        
        import threading
        printer_thread = threading.Thread(target=self.printer.start)
        printer_thread.daemon = True
        printer_thread.start()
        time.sleep(1)
        
        print("3. Creating test configuration...")
        self.create_test_config()
        
        print("4. Starting Print Server...")
        self.start_print_server()
        time.sleep(2)
        
        print()
        print("Setup complete!")
        print("-" * 60)
        print()
    
    def create_test_config(self):
        """Create test configuration file"""
        config = f"""# Integration Test Configuration
API_URL=http://127.0.0.1:{self.api_port}
API_KEY=test-api-key
LOCATION_ID=1
POLL_INTERVAL=1
PRINTER_MAIN=127.0.0.1:{self.printer_port}
DEBUG_LEVEL=INFO
LOG_FILE=/tmp/integration_test_server.log
"""
        with open('config.test.env', 'w') as f:
            f.write(config)
    
    def start_print_server(self):
        """Start the print server process"""
        env = os.environ.copy()
        
        with open('config.test.env', 'r') as f:
            for line in f:
                if '=' in line and not line.startswith('#'):
                    key, value = line.strip().split('=', 1)
                    env[key] = value
        
        self.print_server_process = subprocess.Popen(
            [sys.executable, 'print_server.py'],
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE
        )
    
    def create_order(self, order_type='simple'):
        """Create a test order via API"""
        url = f'http://127.0.0.1:{self.api_port}/api/test/create-order'
        data = json.dumps({'type': order_type, 'location_id': '1'}).encode('utf-8')
        
        req = urllib.request.Request(url, data=data, method='POST')
        req.add_header('Content-Type', 'application/json')
        
        try:
            with urllib.request.urlopen(req) as response:
                order = json.loads(response.read().decode('utf-8'))
                return order
        except Exception as e:
            print(f"Failed to create order: {e}")
            return None
    
    def check_order_printed(self, order_id, timeout=10):
        """Check if order was printed"""
        url = f'http://127.0.0.1:{self.api_port}/api/print-queue?location_id=1'
        req = urllib.request.Request(url)
        req.add_header('X-API-Key', 'test-api-key')
        
        start_time = time.time()
        
        while time.time() - start_time < timeout:
            try:
                with urllib.request.urlopen(req) as response:
                    orders = json.loads(response.read().decode('utf-8'))
                    
                    order_found = False
                    for order in orders:
                        if str(order['id']) == str(order_id):
                            order_found = True
                            if order.get('printed'):
                                return True
                    
                    if not order_found:
                        return True
                    
            except Exception as e:
                print(f"Error checking order status: {e}")
            
            time.sleep(0.5)
        
        return False
    
    def run_tests(self):
        """Run integration tests"""
        print("Running Integration Tests")
        print("=" * 60)
        print()
        
        tests = [
            ('Simple Order', 'simple'),
            ('Complex Order', 'complex'),
            ('Kitchen Order', 'kitchen')
        ]
        
        for test_name, order_type in tests:
            print(f"Test: {test_name}")
            print("-" * 40)
            
            print(f"  Creating {order_type} order...")
            order = self.create_order(order_type)
            
            if order:
                print(f"  Order #{order['id']} created")
                print(f"  Waiting for print...")
                
                if self.check_order_printed(order['id']):
                    print(f"  ✓ Order printed successfully")
                    
                    if os.path.exists('/tmp/integration_test_prints.log'):
                        with open('/tmp/integration_test_prints.log', 'r') as f:
                            content = f.read()
                            if f"Print Job" in content and str(order['id']) in content:
                                print(f"  ✓ Print data verified in log")
                            else:
                                print(f"  ✗ Print data not found in log")
                                self.test_passed = False
                else:
                    print(f"  ✗ Order not printed within timeout")
                    self.test_passed = False
            else:
                print(f"  ✗ Failed to create order")
                self.test_passed = False
            
            print()
        
        self.check_server_health()
        
        print("=" * 60)
        if self.test_passed:
            print("✓ ALL TESTS PASSED")
        else:
            print("✗ SOME TESTS FAILED")
        print("=" * 60)
    
    def check_server_health(self):
        """Check print server health"""
        print("Server Health Check")
        print("-" * 40)
        
        if self.print_server_process and self.print_server_process.poll() is None:
            print("  ✓ Print server is running")
        else:
            print("  ✗ Print server crashed")
            self.test_passed = False
        
        if os.path.exists('/tmp/integration_test_server.log'):
            with open('/tmp/integration_test_server.log', 'r') as f:
                log_content = f.read()
                
                if 'ERROR' in log_content and 'HTTP Error 404' not in log_content:
                    print("  ⚠ Errors found in server log")
                    errors = [line for line in log_content.split('\n') if 'ERROR' in line and 'HTTP Error 404' not in line]
                    for error in errors[:3]:
                        print(f"    {error}")
                else:
                    print("  ✓ No critical errors in log")
        
        print()
    
    def cleanup(self):
        """Clean up test environment"""
        print()
        print("Cleaning up...")
        
        if self.print_server_process:
            self.print_server_process.terminate()
            self.print_server_process.wait(timeout=5)
        
        if self.api_server:
            self.api_server.stop()
        
        if self.printer:
            self.printer.stop()
        
        if os.path.exists('config.test.env'):
            os.remove('config.test.env')
        
        print("Cleanup complete")
    
    def run(self):
        """Run the complete integration test"""
        try:
            self.setup()
            self.run_tests()
        except KeyboardInterrupt:
            print("\nTest interrupted")
        except Exception as e:
            print(f"\nTest failed with error: {e}")
            self.test_passed = False
        finally:
            self.cleanup()
        
        return 0 if self.test_passed else 1


def main():
    """Run integration test"""
    test = IntegrationTest()
    exit_code = test.run()
    sys.exit(exit_code)


if __name__ == '__main__':
    main()