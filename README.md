# FriendlyPOS Print Server

Lightweight Python-based print server for FriendlyPOS that bridges the cloud-based web app with local thermal printers. Designed to run on Teltonika RUT956 routers (OpenWrt) with minimal resource usage.

## Quick Start

### Development Setup

```bash
# Clone the repository
git clone https://github.com/yourusername/friendlypos-print-server.git
cd friendlypos-print-server

# Set up development environment
chmod +x setup.sh
./setup.sh

# Configure
cp config.env.example config.env
# Edit config.env with your API details

# Run locally
./run_dev.sh
```

### Production (Teltonika Router)

```bash
# SSH into router
ssh root@192.168.1.1

# Clone and install
cd /usr/local
git clone https://github.com/yourusername/friendlypos-print-server.git friendlypos
cd friendlypos
./setup.sh

# Configure
cp config.env.example config.env
vi config.env  # Add production credentials

# Enable and start service
/etc/init.d/print_server enable
/etc/init.d/print_server start
```

## Configuration

### Required Settings

- `API_URL`: Your FriendlyPOS API endpoint
- `API_KEY`: Authentication key for API access
- `LOCATION_ID`: Unique identifier for this location

### Optional Settings

- `POLL_INTERVAL`: Seconds between API polls (default: 2)
- `DEBUG_LEVEL`: Logging level (INFO, DEBUG, ERROR)
- `PRINTER_*`: Printer configurations (IP:PORT format)

See `config.env.example` for all available options.

## API Integration

### Endpoints Used

- `GET /api/print-queue` - Fetch pending print jobs
- `GET /api/printers` - Get printer configurations
- `GET /api/settings` - Get event-specific settings
- `PATCH /api/orders/:id/status` - Update order status

### Authentication

API key authentication via header: `X-API-Key: your-key`

## Architecture

### How It Works

1. Print server polls the FriendlyPOS API for pending orders
2. When orders are found, formats them for ESC/POS printing
3. Sends formatted data to configured thermal printers
4. Updates order status in the cloud

### Data Flow

```
FriendlyPOS Cloud → API → Print Server → Thermal Printer
                            ↓
                     Order Status Update
```

## Troubleshooting

### Common Issues

#### Printer Not Responding
```bash
# Test printer connectivity
python3 scripts/test_printer.py 192.168.1.100
```

#### Service Not Starting
```bash
# Check service status
/etc/init.d/print_server status

# View logs
tail -f /tmp/print_server.log
```

#### API Connection Failed
```bash
# Test API connectivity
curl -H "X-API-Key: your-key" https://your-app.vercel.app/api/print-queue
```

### Debug Commands

```bash
# Enable debug mode
export DEBUG_LEVEL=DEBUG
./run_dev.sh

# Monitor resource usage
top -d 1 | grep python

# Check network connections
netstat -an | grep 9100
```

## System Requirements

- Python 3.7+
- OpenWrt 19.07+ (for router deployment)
- Network access to printers (typically port 9100)
- Internet connection for API access
- < 10MB RAM usage
- < 5% CPU usage (average)

## Development

### Testing

```bash
# Run unit tests
python -m pytest tests/

# Test with mock printer
python tests/mock_printer.py &
./run_dev.sh
```

### Contributing

1. Fork the repository
2. Create a feature branch
3. Test thoroughly
4. Submit a pull request

## License

MIT License - See LICENSE file for details

## Support

For issues or questions, please open an issue on GitHub.