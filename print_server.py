#!/usr/bin/env python3
"""
FriendlyPOS Print Server - Teltonika RUT956 Edition
"""

import json
import socket
import time
import urllib.request
import urllib.error
import sys
import os
import logging
from datetime import datetime
from typing import Dict, List, Optional, Any

CONFIG = {
    'api_url': os.getenv('API_URL', 'https://your-app.vercel.app'),
    'api_key': os.getenv('API_KEY', ''),
    'location_id': os.getenv('LOCATION_ID', '1'),
    'poll_interval': int(os.getenv('POLL_INTERVAL', '2')),
    'debug_level': os.getenv('DEBUG_LEVEL', 'INFO'),
    'log_file': os.getenv('LOG_FILE', '/tmp/print_server.log'),
    'retry_attempts': int(os.getenv('RETRY_ATTEMPTS', '3')),
    'retry_delay': int(os.getenv('RETRY_DELAY', '5')),
    'dev_mode': os.getenv('DEV_MODE', '0') == '1'
}

logging.basicConfig(
    level=getattr(logging, CONFIG['debug_level']),
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler(CONFIG['log_file']) if not CONFIG['dev_mode'] else logging.StreamHandler(),
        logging.StreamHandler() if CONFIG['dev_mode'] else logging.NullHandler()
    ]
)

logger = logging.getLogger(__name__)


class ESCPOSCommands:
    """ESC/POS command constants"""
    INIT = b'\x1b\x40'
    CUT = b'\x1d\x56\x00'
    ALIGN_CENTER = b'\x1b\x61\x01'
    ALIGN_LEFT = b'\x1b\x61\x00'
    ALIGN_RIGHT = b'\x1b\x61\x02'
    BOLD_ON = b'\x1b\x45\x01'
    BOLD_OFF = b'\x1b\x45\x00'
    DOUBLE_HEIGHT = b'\x1b\x21\x10'
    NORMAL_SIZE = b'\x1b\x21\x00'
    LINE_FEED = b'\n'


class SimplePrinter:
    """Basic ESC/POS printer communication"""
    
    def __init__(self, host: str, port: int = 9100):
        self.host = host
        self.port = port
        self.socket = None
        self.connected = False
    
    def connect(self) -> bool:
        """Establish TCP connection to printer"""
        try:
            self.socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            self.socket.settimeout(5.0)
            self.socket.connect((self.host, self.port))
            self.connected = True
            logger.info(f"Connected to printer at {self.host}:{self.port}")
            return True
        except Exception as e:
            logger.error(f"Failed to connect to printer {self.host}:{self.port}: {e}")
            self.connected = False
            return False
    
    def send(self, data: bytes) -> bool:
        """Send raw data to printer"""
        if not self.connected:
            if not self.connect():
                return False
        
        try:
            self.socket.send(data)
            return True
        except Exception as e:
            logger.error(f"Failed to send data to printer: {e}")
            self.disconnect()
            return False
    
    def print_order(self, order: Dict[str, Any], settings: Dict[str, Any] = None) -> bool:
        """Format and print order"""
        try:
            data = bytearray()
            
            data.extend(ESCPOSCommands.INIT)
            
            if settings and settings.get('header'):
                data.extend(ESCPOSCommands.ALIGN_CENTER)
                data.extend(ESCPOSCommands.DOUBLE_HEIGHT)
                data.extend(settings['header'].encode('utf-8'))
                data.extend(ESCPOSCommands.LINE_FEED * 2)
            
            data.extend(ESCPOSCommands.NORMAL_SIZE)
            data.extend(ESCPOSCommands.ALIGN_CENTER)
            data.extend(b"ORDER #" + str(order.get('id', 'N/A')).encode('utf-8'))
            data.extend(ESCPOSCommands.LINE_FEED * 2)
            
            data.extend(ESCPOSCommands.ALIGN_LEFT)
            data.extend(b"-" * 32)
            data.extend(ESCPOSCommands.LINE_FEED)
            
            for item in order.get('items', []):
                qty = str(item.get('quantity', 1))
                name = item.get('name', 'Unknown Item')
                price = f"${item.get('price', 0):.2f}"
                
                line = f"{qty}x {name}".ljust(24) + price.rjust(8)
                data.extend(line.encode('utf-8'))
                data.extend(ESCPOSCommands.LINE_FEED)
                
                if item.get('notes'):
                    data.extend(f"  Note: {item['notes']}".encode('utf-8'))
                    data.extend(ESCPOSCommands.LINE_FEED)
            
            data.extend(b"-" * 32)
            data.extend(ESCPOSCommands.LINE_FEED)
            
            total = order.get('total', 0)
            data.extend(ESCPOSCommands.BOLD_ON)
            data.extend(f"TOTAL:".ljust(24).encode('utf-8'))
            data.extend(f"${total:.2f}".rjust(8).encode('utf-8'))
            data.extend(ESCPOSCommands.BOLD_OFF)
            data.extend(ESCPOSCommands.LINE_FEED * 2)
            
            customer = order.get('customer', {})
            if customer.get('name'):
                data.extend(f"Customer: {customer['name']}".encode('utf-8'))
                data.extend(ESCPOSCommands.LINE_FEED)
            if customer.get('phone'):
                data.extend(f"Phone: {customer['phone']}".encode('utf-8'))
                data.extend(ESCPOSCommands.LINE_FEED)
            
            if order.get('notes'):
                data.extend(ESCPOSCommands.LINE_FEED)
                data.extend(b"Notes: " + order['notes'].encode('utf-8'))
                data.extend(ESCPOSCommands.LINE_FEED)
            
            data.extend(ESCPOSCommands.LINE_FEED * 2)
            data.extend(ESCPOSCommands.ALIGN_CENTER)
            data.extend(datetime.now().strftime("%Y-%m-%d %H:%M:%S").encode('utf-8'))
            data.extend(ESCPOSCommands.LINE_FEED * 3)
            
            data.extend(ESCPOSCommands.CUT)
            
            return self.send(bytes(data))
            
        except Exception as e:
            logger.error(f"Failed to format order for printing: {e}")
            return False
    
    def disconnect(self):
        """Close printer connection"""
        if self.socket:
            try:
                self.socket.close()
            except:
                pass
            self.socket = None
            self.connected = False
            logger.info(f"Disconnected from printer {self.host}:{self.port}")


class PrintServer:
    """Main print server application"""
    
    def __init__(self):
        self.config = CONFIG
        self.printers: Dict[str, SimplePrinter] = {}
        self.event_settings = {}
        self.running = False
        self.last_job_id = None
    
    def make_api_request(self, endpoint: str, method: str = 'GET', data: Dict = None) -> Optional[Dict]:
        """Make HTTP request to FriendlyPOS API"""
        url = f"{self.config['api_url']}{endpoint}"
        headers = {
            'X-API-Key': self.config['api_key'],
            'Content-Type': 'application/json'
        }
        
        req = urllib.request.Request(url, headers=headers, method=method)
        
        if data and method in ['POST', 'PATCH', 'PUT']:
            req.data = json.dumps(data).encode('utf-8')
        
        try:
            with urllib.request.urlopen(req) as response:
                return json.loads(response.read().decode('utf-8'))
        except urllib.error.HTTPError as e:
            logger.error(f"HTTP Error {e.code}: {e.reason} for {url}")
            return None
        except Exception as e:
            logger.error(f"API request failed for {url}: {e}")
            return None
    
    def load_printers(self) -> bool:
        """Load printer configurations from API or environment"""
        try:
            api_printers = self.make_api_request('/api/printers')
            
            if api_printers and isinstance(api_printers, list):
                for printer_config in api_printers:
                    if printer_config.get('location_id') == self.config['location_id']:
                        name = printer_config.get('name', 'default')
                        host = printer_config.get('host')
                        port = printer_config.get('port', 9100)
                        
                        if host:
                            self.printers[name] = SimplePrinter(host, port)
                            logger.info(f"Loaded printer '{name}' from API: {host}:{port}")
            
            for key, value in os.environ.items():
                if key.startswith('PRINTER_'):
                    name = key.replace('PRINTER_', '').lower()
                    if ':' in value:
                        host, port = value.split(':')
                        self.printers[name] = SimplePrinter(host, int(port))
                        logger.info(f"Loaded printer '{name}' from env: {host}:{port}")
            
            if not self.printers:
                logger.warning("No printers configured")
                return False
            
            return True
            
        except Exception as e:
            logger.error(f"Failed to load printer configurations: {e}")
            return False
    
    def load_event_settings(self) -> bool:
        """Load event-specific settings from API"""
        try:
            settings = self.make_api_request('/api/settings')
            
            if settings:
                self.event_settings = settings
                logger.info(f"Loaded event settings: {settings.get('event_name', 'Default')}")
                return True
            
            logger.warning("No event settings loaded, using defaults")
            return True
            
        except Exception as e:
            logger.error(f"Failed to load event settings: {e}")
            return False
    
    def poll_for_jobs(self) -> List[Dict]:
        """Check API for pending print jobs"""
        try:
            response = self.make_api_request(
                f'/api/print-queue?location_id={self.config["location_id"]}'
            )
            
            if response and isinstance(response, list):
                new_jobs = []
                for job in response:
                    if job.get('id') != self.last_job_id:
                        new_jobs.append(job)
                        if job.get('id'):
                            self.last_job_id = job['id']
                
                if new_jobs:
                    logger.info(f"Found {len(new_jobs)} new print job(s)")
                
                return new_jobs
            
            return []
            
        except Exception as e:
            logger.error(f"Failed to poll for print jobs: {e}")
            return []
    
    def process_order(self, order: Dict) -> bool:
        """Process and print an order"""
        try:
            printer_name = order.get('printer', 'main')
            printer = self.printers.get(printer_name)
            
            if not printer:
                printer = self.printers.get('main')
                if not printer and self.printers:
                    printer = list(self.printers.values())[0]
            
            if not printer:
                logger.error(f"No printer available for order {order.get('id')}")
                return False
            
            success = False
            for attempt in range(self.config['retry_attempts']):
                if printer.print_order(order, self.event_settings):
                    success = True
                    logger.info(f"Successfully printed order {order.get('id')} on attempt {attempt + 1}")
                    break
                else:
                    logger.warning(f"Print attempt {attempt + 1} failed for order {order.get('id')}")
                    if attempt < self.config['retry_attempts'] - 1:
                        time.sleep(self.config['retry_delay'])
            
            if success and order.get('id'):
                self.make_api_request(
                    f'/api/orders/{order["id"]}/status',
                    method='PATCH',
                    data={'status': 'printed', 'printed_at': datetime.now().isoformat()}
                )
            
            return success
            
        except Exception as e:
            logger.error(f"Failed to process order {order.get('id')}: {e}")
            return False
    
    def run(self):
        """Main server loop"""
        logger.info("Starting FriendlyPOS Print Server")
        logger.info(f"Configuration: Location={self.config['location_id']}, "
                   f"API={self.config['api_url']}, Poll={self.config['poll_interval']}s")
        
        if not self.load_printers():
            logger.error("Failed to load printers, exiting")
            return
        
        self.load_event_settings()
        
        self.running = True
        error_count = 0
        max_errors = 10
        
        try:
            while self.running:
                try:
                    jobs = self.poll_for_jobs()
                    
                    for job in jobs:
                        self.process_order(job)
                    
                    error_count = 0
                    
                except KeyboardInterrupt:
                    raise
                except Exception as e:
                    error_count += 1
                    logger.error(f"Error in main loop (count: {error_count}): {e}")
                    
                    if error_count >= max_errors:
                        logger.critical(f"Too many errors ({max_errors}), exiting")
                        break
                    
                    time.sleep(self.config['retry_delay'])
                
                time.sleep(self.config['poll_interval'])
                
        except KeyboardInterrupt:
            logger.info("Received interrupt signal, shutting down")
        finally:
            self.shutdown()
    
    def shutdown(self):
        """Clean shutdown"""
        self.running = False
        
        for name, printer in self.printers.items():
            printer.disconnect()
        
        logger.info("Print server shutdown complete")


def main():
    """Entry point"""
    if not CONFIG['api_key']:
        logger.error("API_KEY not configured. Please set up config.env")
        sys.exit(1)
    
    server = PrintServer()
    server.run()


if __name__ == "__main__":
    main()