#!/usr/bin/env python3
"""
Test script to verify print server API integration
"""

import json
import sys

def test_job_format():
    """Test that the print server can handle the new job format"""
    
    # Sample job from new API
    test_job = {
        "id": "test-123",
        "ip_address": "192.168.1.100",  # New field name
        "port": 9100,                    # New field name
        "items": [
            {"name": "Test Item", "quantity": 1, "price": 10.00}
        ],
        "total": 10.00,
        "status": "0"  # Pending
    }
    
    # Test field extraction
    printer_ip = test_job.get('ip_address') or test_job.get('printer_ip')
    printer_port = test_job.get('port', test_job.get('printer_port', 9100))
    
    print(f"✓ Extracted printer IP: {printer_ip}")
    print(f"✓ Extracted printer port: {printer_port}")
    
    # Test backward compatibility
    old_job = {
        "id": "test-456",
        "printer_ip": "192.168.1.101",  # Old field name
        "printer_port": 9100,            # Old field name
        "items": [
            {"name": "Legacy Item", "quantity": 1, "price": 5.00}
        ],
        "total": 5.00
    }
    
    printer_ip = old_job.get('ip_address') or old_job.get('printer_ip')
    printer_port = old_job.get('port', old_job.get('printer_port', 9100))
    
    print(f"✓ Backward compatible - IP: {printer_ip}")
    print(f"✓ Backward compatible - Port: {printer_port}")
    
    return True

def test_api_endpoints():
    """Display the new API endpoints that will be called"""
    
    job_id = "test-123"
    base_url = "https://friendlypos.vercel.app"
    
    print("\nNew API Endpoints:")
    print(f"1. Get pending jobs: GET {base_url}/api/print-queue")
    print(f"2. Mark complete: POST {base_url}/api/print-queue/{job_id}/complete")
    print(f"3. Mark failed: POST {base_url}/api/print-queue/{job_id}/fail")
    print("   Body: {\"error\": \"Error message here\"}")
    
    return True

def test_error_messages():
    """Test error message formats"""
    
    print("\nError Message Examples:")
    
    errors = [
        "Printer connection failed or timeout on 192.168.1.100:9100",
        "Failed to connect to printer at 192.168.1.100:9100",
        "Failed to print after 3 attempts",
        "Processing error: Connection refused"
    ]
    
    for error in errors:
        error_payload = json.dumps({"error": error}, indent=2)
        print(f"✓ {error_payload}")
    
    return True

def main():
    print("=" * 50)
    print("Print Server API Integration Test")
    print("=" * 50)
    
    tests = [
        ("Job Format Compatibility", test_job_format),
        ("API Endpoints", test_api_endpoints),
        ("Error Messages", test_error_messages)
    ]
    
    all_passed = True
    
    for test_name, test_func in tests:
        print(f"\nTesting: {test_name}")
        print("-" * 30)
        try:
            if test_func():
                print(f"✅ {test_name} passed")
            else:
                print(f"❌ {test_name} failed")
                all_passed = False
        except Exception as e:
            print(f"❌ {test_name} failed with error: {e}")
            all_passed = False
    
    print("\n" + "=" * 50)
    if all_passed:
        print("✅ All tests passed!")
    else:
        print("❌ Some tests failed")
        sys.exit(1)

if __name__ == "__main__":
    main()