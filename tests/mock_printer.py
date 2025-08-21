#!/usr/bin/env python3
"""
Mock ESC/POS Printer Emulator
Listens on port 9100 and logs all received data for testing
"""

import socket
import threading
import sys
import time
import argparse
from datetime import datetime


class MockPrinter:
    """Emulates an ESC/POS thermal printer for testing"""
    
    ESC_POS_COMMANDS = {
        b'\x1b\x40': 'INIT',
        b'\x1d\x56\x00': 'CUT',
        b'\x1b\x61\x00': 'ALIGN_LEFT',
        b'\x1b\x61\x01': 'ALIGN_CENTER',
        b'\x1b\x61\x02': 'ALIGN_RIGHT',
        b'\x1b\x45\x01': 'BOLD_ON',
        b'\x1b\x45\x00': 'BOLD_OFF',
        b'\x1b\x21\x10': 'DOUBLE_HEIGHT',
        b'\x1b\x21\x00': 'NORMAL_SIZE',
        b'\n': 'LINE_FEED'
    }
    
    def __init__(self, host='0.0.0.0', port=9100, verbose=True, log_file=None):
        self.host = host
        self.port = port
        self.verbose = verbose
        self.log_file = log_file
        self.running = False
        self.server_socket = None
        self.print_count = 0
        self.last_print_data = None
    
    def decode_escpos(self, data):
        """Decode ESC/POS commands for logging"""
        output = []
        i = 0
        
        while i < len(data):
            command_found = False
            
            for cmd_bytes, cmd_name in self.ESC_POS_COMMANDS.items():
                if data[i:i+len(cmd_bytes)] == cmd_bytes:
                    output.append(f"[{cmd_name}]")
                    i += len(cmd_bytes)
                    command_found = True
                    break
            
            if not command_found:
                if 32 <= data[i] <= 126:
                    output.append(chr(data[i]))
                else:
                    output.append(f"[0x{data[i]:02x}]")
                i += 1
        
        return ''.join(output)
    
    def handle_client(self, client_socket, address):
        """Handle incoming print job"""
        print(f"\n{'='*60}")
        print(f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] Connection from {address}")
        print(f"{'='*60}")
        
        self.print_count += 1
        data_buffer = bytearray()
        
        try:
            while True:
                data = client_socket.recv(1024)
                if not data:
                    break
                
                data_buffer.extend(data)
                
                if self.verbose:
                    print(f"Received {len(data)} bytes")
        
        except Exception as e:
            print(f"Error receiving data: {e}")
        
        finally:
            client_socket.close()
        
        if data_buffer:
            self.last_print_data = bytes(data_buffer)
            
            print(f"\n--- Print Job #{self.print_count} ---")
            print(f"Total bytes: {len(data_buffer)}")
            print("\n--- Decoded Content ---")
            
            decoded = self.decode_escpos(data_buffer)
            print(decoded)
            
            if self.log_file:
                with open(self.log_file, 'a') as f:
                    f.write(f"\n{'='*60}\n")
                    f.write(f"Print Job #{self.print_count} - {datetime.now()}\n")
                    f.write(f"From: {address}\n")
                    f.write(f"Bytes: {len(data_buffer)}\n")
                    f.write(f"{'='*60}\n")
                    f.write(decoded)
                    f.write("\n")
            
            print(f"\n--- Raw Hex (first 200 bytes) ---")
            hex_display = ' '.join([f'{b:02x}' for b in data_buffer[:200]])
            print(hex_display)
            
            if len(data_buffer) > 200:
                print(f"... ({len(data_buffer) - 200} more bytes)")
        
        print(f"\n{'='*60}\n")
    
    def start(self):
        """Start the mock printer server"""
        self.server_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.server_socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        
        try:
            self.server_socket.bind((self.host, self.port))
            self.server_socket.listen(5)
            self.running = True
            
            print(f"Mock Printer Server Started")
            print(f"Listening on {self.host}:{self.port}")
            print(f"Verbose: {self.verbose}")
            if self.log_file:
                print(f"Logging to: {self.log_file}")
            print(f"Press Ctrl+C to stop\n")
            
            while self.running:
                try:
                    client_socket, address = self.server_socket.accept()
                    client_thread = threading.Thread(
                        target=self.handle_client,
                        args=(client_socket, address)
                    )
                    client_thread.daemon = True
                    client_thread.start()
                except KeyboardInterrupt:
                    break
                except Exception as e:
                    if self.running:
                        print(f"Error accepting connection: {e}")
        
        except Exception as e:
            print(f"Failed to start server: {e}")
        
        finally:
            self.stop()
    
    def stop(self):
        """Stop the mock printer server"""
        self.running = False
        if self.server_socket:
            self.server_socket.close()
        
        print(f"\nMock Printer Server Stopped")
        print(f"Total print jobs received: {self.print_count}")


def main():
    parser = argparse.ArgumentParser(description='Mock ESC/POS Printer Emulator')
    parser.add_argument('--host', default='0.0.0.0', help='Host to bind to (default: 0.0.0.0)')
    parser.add_argument('--port', type=int, default=9100, help='Port to listen on (default: 9100)')
    parser.add_argument('--quiet', action='store_true', help='Reduce verbosity')
    parser.add_argument('--log', help='Log file path')
    
    args = parser.parse_args()
    
    printer = MockPrinter(
        host=args.host,
        port=args.port,
        verbose=not args.quiet,
        log_file=args.log
    )
    
    try:
        printer.start()
    except KeyboardInterrupt:
        print("\nShutting down...")
        sys.exit(0)


if __name__ == '__main__':
    main()