# FriendlyPOS Print Server

Print server solution for FriendlyPOS that bridges the cloud-based web app with local thermal printers (Epson TM-m30). Optimized for Teltonika RUT956 routers with BusyBox shell environment.

## ⚡ Quick Start (Teltonika RUT956)

### The Working Solution

Due to limitations on Teltonika routers (no `base64` command, limited Python), use the AWK decoder version:

```bash
# Copy the working script to router
scp teltonika-awk-decoder.sh root@192.168.1.1:/root/

# SSH into router
ssh root@192.168.1.1

# Make executable and run
chmod +x /root/teltonika-awk-decoder.sh
/root/teltonika-awk-decoder.sh &

# Monitor logs
tail -f /tmp/printserver.log
```

### Make Permanent (Auto-start on boot)

```bash
# Add to startup
echo "/root/teltonika-awk-decoder.sh &" >> /etc/rc.local

# OR create init script
cat > /etc/init.d/printserver << 'EOF'
#!/bin/sh /etc/rc.common
START=99

start() {
    /root/teltonika-awk-decoder.sh &
}

stop() {
    killall teltonika-awk-decoder.sh 2>/dev/null
}
EOF

chmod +x /etc/init.d/printserver
/etc/init.d/printserver enable
```

## 🔧 Technical Details

### The Problem
Teltonika RUT956 routers running BusyBox have:
- ❌ No `base64` command
- ❌ Limited Python (no socket module)
- ❌ Shell binary handling issues that corrupt ESC/POS data

### The Solution
`teltonika-awk-decoder.sh` uses:
- ✅ Pure AWK for Base64 decoding (built into BusyBox)
- ✅ Direct piping to `nc` (netcat) to preserve binary data
- ✅ `printf` for ESC/POS command generation
- ✅ Fallback text mode if Base64 data is unavailable

### How It Works

1. Polls the API every 2 seconds for pending print jobs
2. Decodes Base64 print data using AWK
3. Sends binary ESC/POS commands directly to printer via netcat
4. Updates order status via API (complete/failed)

## 📁 Key Files

- `teltonika-awk-decoder.sh` - Main working script for Teltonika routers
- `test-awk-decoder.sh` - Test script to verify Base64 decoding works
- `teltonika-debug-binary.sh` - Debug script to diagnose printing issues
- `TELTONIKA-FIX-DEPLOYMENT.md` - Detailed deployment guide

## Development Setup (Python Version)

For development or non-Teltonika environments with full Python support:

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

# Run Python version
python3 print_server.py
```
## Configuration

### Required Settings

- `API_URL`: Your FriendlyPOS API endpoint
- `API_KEY`: Authentication key for API access

### Optional Settings

- `POLL_INTERVAL`: Seconds between API polls (default: 2)
- `DEBUG_LEVEL`: Logging level (INFO, DEBUG, ERROR)

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