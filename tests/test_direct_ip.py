#!/usr/bin/env python3
"""
Test direct IP printing functionality
"""

import sys
import os
import json
import time
import threading

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import print_server
from tests.mock_printer import MockPrinter


def test_direct_ip_printing():
    """Test that print server can print to IP specified in order"""
    
    print("Testing Direct IP Printing")
    print("=" * 60)
    
    # 1. Start mock printer on port 9102
    mock_printer = MockPrinter(
        host='127.0.0.1',
        port=9102,
        verbose=False,
        log_file='/tmp/test_direct_ip.log'
    )
    
    printer_thread = threading.Thread(target=mock_printer.start)
    printer_thread.daemon = True
    printer_thread.start()
    time.sleep(1)
    
    print("✓ Mock printer started on 127.0.0.1:9102")
    
    # 2. Create print server instance
    server = print_server.PrintServer()
    print("✓ Print server initialized")
    
    # 3. Test with direct IP order
    order_with_ip = {
        'id': 'TEST-001',
        'printer_ip': '127.0.0.1',
        'printer_port': 9102,
        'items': [
            {'quantity': 1, 'name': 'Direct IP Test', 'price': 10.00}
        ],
        'total': 10.00,
        'customer': {'name': 'IP Test Customer'},
        'notes': 'This should print to 127.0.0.1:9102'
    }
    
    print("\nTesting order with direct IP...")
    success = server.process_order(order_with_ip)
    
    if success:
        print("✓ Order printed successfully via direct IP")
    else:
        print("✗ Failed to print via direct IP")
        return False
    
    # 4. Verify print was received
    time.sleep(0.5)
    with open('/tmp/test_direct_ip.log', 'r') as f:
        log_content = f.read()
        if 'Direct IP Test' in log_content and 'TEST-001' in log_content:
            print("✓ Print data verified in log")
        else:
            print("✗ Print data not found in log")
            return False
    
    # 5. Test security - reject public IP
    print("\nTesting security (rejecting public IP)...")
    order_with_public_ip = {
        'id': 'TEST-002',
        'printer_ip': '8.8.8.8',  # Google DNS - public IP
        'printer_port': 9102,
        'items': [{'quantity': 1, 'name': 'Should Not Print', 'price': 10.00}],
        'total': 10.00
    }
    
    success = server.process_order(order_with_public_ip)
    
    if not success:
        print("✓ Correctly rejected public IP address")
    else:
        print("✗ Security failure: accepted public IP")
        return False
    
    # 6. Test fallback to named printer
    print("\nTesting fallback to named printer...")
    # Configure a named printer
    server.printers['test'] = print_server.SimplePrinter('127.0.0.1', 9102)
    
    order_with_name = {
        'id': 'TEST-003',
        'printer': 'test',  # Use named printer
        'items': [{'quantity': 1, 'name': 'Named Printer Test', 'price': 5.00}],
        'total': 5.00
    }
    
    success = server.process_order(order_with_name)
    
    if success:
        print("✓ Named printer still works")
    else:
        print("✗ Named printer failed")
        return False
    
    # Clean up
    mock_printer.stop()
    
    print("\n" + "=" * 60)
    print("✓ ALL DIRECT IP TESTS PASSED")
    print("=" * 60)
    
    return True


def test_ip_validation():
    """Test IP address validation"""
    
    print("\nTesting IP Validation")
    print("-" * 40)
    
    server = print_server.PrintServer()
    
    test_cases = [
        # Private IPs (should pass)
        ('192.168.1.100', True, 'Private: 192.168.x.x'),
        ('10.0.0.1', True, 'Private: 10.x.x.x'),
        ('172.16.0.1', True, 'Private: 172.16.x.x'),
        ('172.31.255.254', True, 'Private: 172.31.x.x'),
        ('127.0.0.1', True, 'Localhost'),
        
        # Public IPs (should fail)
        ('8.8.8.8', False, 'Public: Google DNS'),
        ('1.1.1.1', False, 'Public: Cloudflare'),
        ('172.32.0.1', False, 'Public: Outside private range'),
        ('192.169.0.1', False, 'Public: Outside 192.168'),
        
        # Invalid IPs (should fail)
        ('256.256.256.256', False, 'Invalid: Out of range'),
        ('192.168.1', False, 'Invalid: Incomplete'),
        ('not.an.ip', False, 'Invalid: Not numeric'),
    ]
    
    all_passed = True
    
    for ip, expected, description in test_cases:
        result = server._is_private_ip(ip)
        if result == expected:
            print(f"  ✓ {description}: {ip}")
        else:
            print(f"  ✗ {description}: {ip} (expected {expected}, got {result})")
            all_passed = False
    
    if all_passed:
        print("\n✓ All IP validation tests passed")
    else:
        print("\n✗ Some IP validation tests failed")
    
    return all_passed


if __name__ == '__main__':
    # Run tests
    if test_ip_validation() and test_direct_ip_printing():
        print("\n✅ All tests passed!")
        sys.exit(0)
    else:
        print("\n❌ Tests failed!")
        sys.exit(1)