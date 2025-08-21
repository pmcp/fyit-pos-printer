#!/usr/bin/env python3
"""
Test Printer Connectivity and Send Test Print
"""

import socket
import sys
import argparse
from datetime import datetime


class PrinterTester:
    """Test thermal printer connectivity and functionality"""
    
    def __init__(self, host, port=9100):
        self.host = host
        self.port = port
    
    def test_connection(self, timeout=5):
        """Test if printer is reachable"""
        print(f"Testing connection to {self.host}:{self.port}...")
        
        try:
            sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            sock.settimeout(timeout)
            result = sock.connect_ex((self.host, self.port))
            sock.close()
            
            if result == 0:
                print(f"✓ Successfully connected to {self.host}:{self.port}")
                return True
            else:
                print(f"✗ Failed to connect: Connection refused")
                return False
                
        except socket.gaierror:
            print(f"✗ Failed to connect: Invalid hostname or IP")
            return False
        except socket.timeout:
            print(f"✗ Failed to connect: Connection timeout")
            return False
        except Exception as e:
            print(f"✗ Failed to connect: {e}")
            return False
    
    def send_test_print(self, test_type='basic'):
        """Send a test print to the printer"""
        
        test_prints = {
            'basic': self.create_basic_test(),
            'full': self.create_full_test(),
            'alignment': self.create_alignment_test(),
            'barcode': self.create_barcode_test()
        }
        
        if test_type not in test_prints:
            print(f"Unknown test type: {test_type}")
            print(f"Available types: {', '.join(test_prints.keys())}")
            return False
        
        print(f"Sending {test_type} test print...")
        
        try:
            sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            sock.settimeout(10)
            sock.connect((self.host, self.port))
            
            data = test_prints[test_type]
            sock.send(data)
            
            sock.close()
            
            print(f"✓ Test print sent successfully ({len(data)} bytes)")
            return True
            
        except Exception as e:
            print(f"✗ Failed to send test print: {e}")
            return False
    
    def create_basic_test(self):
        """Create a basic test print"""
        ESC = b'\x1b'
        GS = b'\x1d'
        
        data = bytearray()
        
        data.extend(ESC + b'@')
        
        data.extend(ESC + b'a\x01')
        data.extend(ESC + b'!\x10')
        data.extend(b'PRINTER TEST\n')
        
        data.extend(ESC + b'!\x00')
        data.extend(b'-' * 32 + b'\n')
        
        data.extend(ESC + b'a\x00')
        data.extend(f'Date: {datetime.now().strftime("%Y-%m-%d %H:%M:%S")}\n'.encode())
        data.extend(f'Printer: {self.host}:{self.port}\n'.encode())
        data.extend(b'Status: Working\n')
        
        data.extend(b'-' * 32 + b'\n')
        data.extend(b'This is a test print\n')
        data.extend(b'If you can read this,\n')
        data.extend(b'your printer is working!\n')
        
        data.extend(b'\n' * 3)
        
        data.extend(GS + b'V\x00')
        
        return bytes(data)
    
    def create_full_test(self):
        """Create a comprehensive test print"""
        ESC = b'\x1b'
        GS = b'\x1d'
        
        data = bytearray()
        
        data.extend(ESC + b'@')
        
        data.extend(ESC + b'a\x01')
        data.extend(ESC + b'!\x30')
        data.extend(b'FULL TEST\n')
        data.extend(ESC + b'!\x00')
        data.extend(b'\n')
        
        data.extend(ESC + b'a\x00')
        data.extend(b'=== Text Styles ===\n')
        data.extend(ESC + b'E\x01')
        data.extend(b'Bold Text\n')
        data.extend(ESC + b'E\x00')
        
        data.extend(ESC + b'!\x01')
        data.extend(b'Small Text\n')
        data.extend(ESC + b'!\x00')
        
        data.extend(ESC + b'!\x10')
        data.extend(b'Double Height\n')
        data.extend(ESC + b'!\x00')
        
        data.extend(ESC + b'!\x20')
        data.extend(b'Double Width\n')
        data.extend(ESC + b'!\x00')
        
        data.extend(b'\n')
        data.extend(b'=== Special Characters ===\n')
        data.extend('Currency: $ € £ ¥\n'.encode('utf-8'))
        data.extend(b'Symbols: @ # % & * + - = / \\ | ~ ` ^ \n')
        data.extend(b'Numbers: 0123456789\n')
        data.extend(b'Letters: ABCDEFGHIJKLMNOPQRSTUVWXYZ\n')
        data.extend(b'         abcdefghijklmnopqrstuvwxyz\n')
        
        data.extend(b'\n')
        data.extend(b'=== Line Drawing ===\n')
        data.extend(('-' * 32 + '\n').encode('utf-8'))
        data.extend(('=' * 32 + '\n').encode('utf-8'))
        data.extend(b'.' * 32 + b'\n')
        data.extend(b'*' * 32 + b'\n')
        
        data.extend(b'\n' * 3)
        
        data.extend(GS + b'V\x00')
        
        return bytes(data)
    
    def create_alignment_test(self):
        """Create an alignment test print"""
        ESC = b'\x1b'
        GS = b'\x1d'
        
        data = bytearray()
        
        data.extend(ESC + b'@')
        
        data.extend(ESC + b'a\x01')
        data.extend(b'ALIGNMENT TEST\n')
        data.extend(b'-' * 32 + b'\n')
        
        data.extend(ESC + b'a\x00')
        data.extend(b'Left Aligned Text\n')
        
        data.extend(ESC + b'a\x01')
        data.extend(b'Center Aligned Text\n')
        
        data.extend(ESC + b'a\x02')
        data.extend(b'Right Aligned Text\n')
        
        data.extend(ESC + b'a\x00')
        data.extend(b'\n')
        
        for i in range(3):
            data.extend(b'Column 1    Column 2    Column 3\n')
        
        data.extend(b'\n')
        data.extend(b'Item                        Price\n')
        data.extend(b'-' * 32 + b'\n')
        data.extend(b'Coffee                      $3.50\n')
        data.extend(b'Sandwich                    $8.00\n')
        data.extend(b'Cookie                      $2.25\n')
        data.extend(b'-' * 32 + b'\n')
        data.extend(b'TOTAL                      $13.75\n')
        
        data.extend(b'\n' * 3)
        
        data.extend(GS + b'V\x00')
        
        return bytes(data)
    
    def create_barcode_test(self):
        """Create a barcode test print (if printer supports it)"""
        ESC = b'\x1b'
        GS = b'\x1d'
        
        data = bytearray()
        
        data.extend(ESC + b'@')
        
        data.extend(ESC + b'a\x01')
        data.extend(b'BARCODE TEST\n')
        data.extend(b'-' * 32 + b'\n')
        data.extend(ESC + b'a\x00')
        
        data.extend(b'Code 39:\n')
        data.extend(GS + b'h\x50')
        data.extend(GS + b'w\x02')
        data.extend(GS + b'k\x04')
        data.extend(b'TEST123\x00')
        data.extend(b'\n')
        
        data.extend(b'Code 128:\n')
        data.extend(GS + b'k\x49\x08')
        data.extend(b'{BTEST128')
        data.extend(b'\n')
        
        data.extend(b'QR Code (if supported):\n')
        data.extend(GS + b'(k\x04\x001\x41\x32\x00')
        data.extend(GS + b'(k\x03\x001\x43\x03')
        data.extend(GS + b'(k\x0b\x001\x50\x30')
        data.extend(b'HELLO QR')
        data.extend(GS + b'(k\x03\x001\x51\x30')
        
        data.extend(b'\n' * 3)
        
        data.extend(GS + b'V\x00')
        
        return bytes(data)
    
    def scan_network(self, base_ip, start=1, end=254):
        """Scan network for printers"""
        print(f"Scanning {base_ip}.{start}-{end} on port {self.port}...")
        found_printers = []
        
        for i in range(start, end + 1):
            ip = f"{base_ip}.{i}"
            sys.stdout.write(f"\rScanning: {ip}...")
            sys.stdout.flush()
            
            try:
                sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
                sock.settimeout(0.1)
                result = sock.connect_ex((ip, self.port))
                sock.close()
                
                if result == 0:
                    found_printers.append(ip)
                    print(f"\n✓ Found printer at {ip}")
            except:
                pass
        
        print(f"\n\nScan complete. Found {len(found_printers)} printer(s)")
        return found_printers


def main():
    parser = argparse.ArgumentParser(description='Test thermal printer connectivity')
    parser.add_argument('host', help='Printer IP address or hostname')
    parser.add_argument('--port', type=int, default=9100, help='Printer port (default: 9100)')
    parser.add_argument('--test', choices=['basic', 'full', 'alignment', 'barcode'],
                       default='basic', help='Type of test print')
    parser.add_argument('--scan', action='store_true', help='Scan network for printers')
    parser.add_argument('--no-print', action='store_true', help='Only test connection')
    
    args = parser.parse_args()
    
    if args.scan:
        base_ip = '.'.join(args.host.split('.')[:-1])
        tester = PrinterTester('0.0.0.0', args.port)
        printers = tester.scan_network(base_ip)
        
        if printers and not args.no_print:
            print("\nTest print to found printers? (y/n): ", end='')
            if input().lower() == 'y':
                for ip in printers:
                    print(f"\nTesting {ip}...")
                    tester = PrinterTester(ip, args.port)
                    tester.send_test_print('basic')
    else:
        tester = PrinterTester(args.host, args.port)
        
        if tester.test_connection():
            if not args.no_print:
                tester.send_test_print(args.test)
        else:
            sys.exit(1)


if __name__ == '__main__':
    main()