#!/usr/bin/env python3
"""
Unit tests for FriendlyPOS Print Server
"""

import unittest
import json
import socket
import sys
import os
from unittest.mock import Mock, patch, MagicMock
from datetime import datetime

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import print_server


class TestSimplePrinter(unittest.TestCase):
    """Test SimplePrinter class"""
    
    def setUp(self):
        self.printer = print_server.SimplePrinter('127.0.0.1', 9100)
    
    def test_init(self):
        """Test printer initialization"""
        self.assertEqual(self.printer.host, '127.0.0.1')
        self.assertEqual(self.printer.port, 9100)
        self.assertFalse(self.printer.connected)
        self.assertIsNone(self.printer.socket)
    
    @patch('socket.socket')
    def test_connect_success(self, mock_socket):
        """Test successful printer connection"""
        mock_sock_instance = Mock()
        mock_socket.return_value = mock_sock_instance
        
        result = self.printer.connect()
        
        self.assertTrue(result)
        self.assertTrue(self.printer.connected)
        mock_sock_instance.connect.assert_called_once_with(('127.0.0.1', 9100))
    
    @patch('socket.socket')
    def test_connect_failure(self, mock_socket):
        """Test failed printer connection"""
        mock_sock_instance = Mock()
        mock_sock_instance.connect.side_effect = ConnectionRefusedError()
        mock_socket.return_value = mock_sock_instance
        
        result = self.printer.connect()
        
        self.assertFalse(result)
        self.assertFalse(self.printer.connected)
    
    @patch('socket.socket')
    def test_send_data(self, mock_socket):
        """Test sending data to printer"""
        mock_sock_instance = Mock()
        mock_socket.return_value = mock_sock_instance
        
        self.printer.connect()
        result = self.printer.send(b'TEST DATA')
        
        self.assertTrue(result)
        mock_sock_instance.send.assert_called_once_with(b'TEST DATA')
    
    def test_print_order_formatting(self):
        """Test order formatting for printing"""
        order = {
            'id': '123',
            'items': [
                {'quantity': 2, 'name': 'Coffee', 'price': 3.50},
                {'quantity': 1, 'name': 'Sandwich', 'price': 8.00, 'notes': 'No onions'}
            ],
            'total': 15.00,
            'customer': {'name': 'John Doe', 'phone': '555-1234'},
            'notes': 'Rush order'
        }
        
        settings = {
            'header': 'FRIENDLY CAFE'
        }
        
        with patch.object(self.printer, 'send') as mock_send:
            mock_send.return_value = True
            result = self.printer.print_order(order, settings)
            
            self.assertTrue(result)
            
            call_args = mock_send.call_args[0][0]
            self.assertIn(b'FRIENDLY CAFE', call_args)
            self.assertIn(b'ORDER #123', call_args)
            self.assertIn(b'2x Coffee', call_args)
            self.assertIn(b'$3.50', call_args)
            self.assertIn(b'1x Sandwich', call_args)
            self.assertIn(b'No onions', call_args)
            self.assertIn(b'TOTAL:', call_args)
            self.assertIn(b'$15.00', call_args)
            self.assertIn(b'John Doe', call_args)
            self.assertIn(b'555-1234', call_args)
            self.assertIn(b'Rush order', call_args)


class TestPrintServer(unittest.TestCase):
    """Test PrintServer class"""
    
    def setUp(self):
        self.original_config = print_server.CONFIG.copy()
        print_server.CONFIG.update({
            'api_url': 'http://test.local',
            'api_key': 'test-key',
            'location_id': '1',
            'poll_interval': 2,
            'retry_attempts': 3,
            'retry_delay': 1
        })
        self.server = print_server.PrintServer()
    
    def tearDown(self):
        print_server.CONFIG = self.original_config
    
    def test_init(self):
        """Test server initialization"""
        self.assertEqual(self.server.config['api_url'], 'http://test.local')
        self.assertEqual(self.server.config['api_key'], 'test-key')
        self.assertEqual(self.server.config['location_id'], '1')
        self.assertFalse(self.server.running)
        self.assertIsNone(self.server.last_job_id)
    
    @patch('urllib.request.urlopen')
    def test_make_api_request_get(self, mock_urlopen):
        """Test GET API request"""
        mock_response = Mock()
        mock_response.read.return_value = b'{"status": "ok"}'
        mock_urlopen.return_value.__enter__.return_value = mock_response
        
        result = self.server.make_api_request('/api/test')
        
        self.assertEqual(result, {'status': 'ok'})
        
        call_args = mock_urlopen.call_args[0][0]
        self.assertEqual(call_args.full_url, 'http://test.local/api/test')
        self.assertEqual(call_args.headers['X-api-key'], 'test-key')
        self.assertEqual(call_args.method, 'GET')
    
    @patch('urllib.request.urlopen')
    def test_make_api_request_post(self, mock_urlopen):
        """Test POST API request"""
        mock_response = Mock()
        mock_response.read.return_value = b'{"created": true}'
        mock_urlopen.return_value.__enter__.return_value = mock_response
        
        data = {'test': 'data'}
        result = self.server.make_api_request('/api/create', method='POST', data=data)
        
        self.assertEqual(result, {'created': True})
        
        call_args = mock_urlopen.call_args[0][0]
        self.assertEqual(call_args.method, 'POST')
        self.assertEqual(json.loads(call_args.data), data)
    
    @patch.object(print_server.PrintServer, 'make_api_request')
    @patch.dict(os.environ, {'PRINTER_KITCHEN': '192.168.1.101:9100'})
    def test_load_printers(self, mock_api):
        """Test loading printer configurations"""
        mock_api.return_value = [
            {
                'location_id': '1',
                'name': 'main',
                'host': '192.168.1.100',
                'port': 9100
            }
        ]
        
        result = self.server.load_printers()
        
        self.assertTrue(result)
        self.assertIn('main', self.server.printers)
        self.assertIn('kitchen', self.server.printers)
        self.assertEqual(self.server.printers['main'].host, '192.168.1.100')
        self.assertEqual(self.server.printers['kitchen'].host, '192.168.1.101')
    
    @patch.object(print_server.PrintServer, 'make_api_request')
    def test_load_event_settings(self, mock_api):
        """Test loading event settings"""
        mock_api.return_value = {
            'event_name': 'Summer Festival',
            'header': 'SUMMER FEST 2024',
            'footer': 'Thank you!'
        }
        
        result = self.server.load_event_settings()
        
        self.assertTrue(result)
        self.assertEqual(self.server.event_settings['event_name'], 'Summer Festival')
        self.assertEqual(self.server.event_settings['header'], 'SUMMER FEST 2024')
    
    @patch.object(print_server.PrintServer, 'make_api_request')
    def test_poll_for_jobs(self, mock_api):
        """Test polling for print jobs"""
        mock_api.return_value = [
            {'id': '1', 'order': 'data1'},
            {'id': '2', 'order': 'data2'}
        ]
        
        jobs = self.server.poll_for_jobs()
        
        self.assertEqual(len(jobs), 2)
        self.assertEqual(jobs[0]['id'], '1')
        self.assertEqual(jobs[1]['id'], '2')
        self.assertEqual(self.server.last_job_id, '2')
        
        mock_api.return_value = [
            {'id': '2', 'order': 'data2'},
            {'id': '3', 'order': 'data3'}
        ]
        
        jobs = self.server.poll_for_jobs()
        
        self.assertEqual(len(jobs), 1)
        self.assertEqual(jobs[0]['id'], '3')
        self.assertEqual(self.server.last_job_id, '3')
    
    @patch.object(print_server.PrintServer, 'make_api_request')
    def test_process_order(self, mock_api):
        """Test order processing"""
        mock_printer = Mock()
        mock_printer.print_order.return_value = True
        self.server.printers = {'main': mock_printer}
        
        order = {
            'id': '123',
            'printer': 'main',
            'items': []
        }
        
        result = self.server.process_order(order)
        
        self.assertTrue(result)
        mock_printer.print_order.assert_called_once()
        
        mock_api.assert_called_with(
            '/api/orders/123/status',
            method='PATCH',
            data={'status': 'printed', 'printed_at': unittest.mock.ANY}
        )
    
    @patch.object(print_server.PrintServer, 'make_api_request')
    def test_process_order_retry(self, mock_api):
        """Test order processing with retries"""
        mock_printer = Mock()
        mock_printer.print_order.side_effect = [False, False, True]
        self.server.printers = {'main': mock_printer}
        
        order = {'id': '123', 'items': []}
        
        with patch('time.sleep'):
            result = self.server.process_order(order)
        
        self.assertTrue(result)
        self.assertEqual(mock_printer.print_order.call_count, 3)
    
    @patch.object(print_server.PrintServer, 'make_api_request')
    def test_process_order_all_retries_fail(self, mock_api):
        """Test order processing when all retries fail"""
        mock_printer = Mock()
        mock_printer.print_order.return_value = False
        self.server.printers = {'main': mock_printer}
        
        order = {'id': '123', 'items': []}
        
        with patch('time.sleep'):
            result = self.server.process_order(order)
        
        self.assertFalse(result)
        self.assertEqual(mock_printer.print_order.call_count, 3)
        mock_api.assert_not_called()


class TestESCPOSCommands(unittest.TestCase):
    """Test ESC/POS command constants"""
    
    def test_commands_are_bytes(self):
        """Test that all commands are bytes"""
        commands = [
            print_server.ESCPOSCommands.INIT,
            print_server.ESCPOSCommands.CUT,
            print_server.ESCPOSCommands.ALIGN_CENTER,
            print_server.ESCPOSCommands.ALIGN_LEFT,
            print_server.ESCPOSCommands.ALIGN_RIGHT,
            print_server.ESCPOSCommands.BOLD_ON,
            print_server.ESCPOSCommands.BOLD_OFF,
            print_server.ESCPOSCommands.DOUBLE_HEIGHT,
            print_server.ESCPOSCommands.NORMAL_SIZE,
            print_server.ESCPOSCommands.LINE_FEED
        ]
        
        for cmd in commands:
            self.assertIsInstance(cmd, bytes)
    
    def test_command_values(self):
        """Test specific command values"""
        self.assertEqual(print_server.ESCPOSCommands.INIT, b'\x1b\x40')
        self.assertEqual(print_server.ESCPOSCommands.CUT, b'\x1d\x56\x00')
        self.assertEqual(print_server.ESCPOSCommands.LINE_FEED, b'\n')


class TestIntegration(unittest.TestCase):
    """Integration tests"""
    
    @patch('urllib.request.urlopen')
    @patch('socket.socket')
    def test_full_print_flow(self, mock_socket, mock_urlopen):
        """Test complete print flow from API to printer"""
        mock_sock_instance = Mock()
        mock_socket.return_value = mock_sock_instance
        
        api_responses = [
            b'[{"location_id": "1", "name": "main", "host": "127.0.0.1", "port": 9100}]',
            b'{"event_name": "Test Event", "header": "TEST HEADER"}',
            b'[{"id": "999", "items": [{"quantity": 1, "name": "Test Item", "price": 10.00}], "total": 10.00}]',
            b'{"status": "updated"}'
        ]
        
        mock_response = Mock()
        mock_response.read.side_effect = api_responses
        mock_urlopen.return_value.__enter__.return_value = mock_response
        
        server = print_server.PrintServer()
        
        self.assertTrue(server.load_printers())
        self.assertTrue(server.load_event_settings())
        
        jobs = server.poll_for_jobs()
        self.assertEqual(len(jobs), 1)
        
        result = server.process_order(jobs[0])
        self.assertTrue(result)
        
        mock_sock_instance.send.assert_called_once()
        sent_data = mock_sock_instance.send.call_args[0][0]
        self.assertIn(b'TEST HEADER', sent_data)
        self.assertIn(b'Test Item', sent_data)
        self.assertIn(b'$10.00', sent_data)


if __name__ == '__main__':
    unittest.main()