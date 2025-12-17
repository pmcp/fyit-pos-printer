# Teltonika RUT956 Print Server Setup for Crouton-Sales

## Quick Start

1. **Copy script to router:**
```bash
scp teltonika-simple-spooler-fast.sh root@192.168.1.1:/tmp/friendlypos_server.sh
```

2. **SSH into router and run:**
```bash
ssh root@192.168.1.1
/tmp/friendlypos_server.sh
```

## Network Setup

### Finding IP Addresses

1. **Your Mac's IP** (the one the router can reach):
```bash
ifconfig | grep "inet " | grep -v 127.0.0.1
```
Look for an IP in the same subnet as the router (e.g., 192.168.1.x)

2. **Router IP**: Usually `192.168.1.1` (check your network settings)

3. **Printer IP**: The Epson TM-m30 printer prints its IP when powered on, or check router's DHCP leases

### Network Requirements

- Your Mac must be reachable from the router (same subnet or routed)
- Printer must be on the same network as the router (192.168.1.x)
- Crouton-sales must be running with `HOST=0.0.0.0` to accept connections from the router

## Configuration

The script uses environment variables with defaults:

```bash
API_URL="${API_URL:-http://192.168.1.214:3000}"  # Your Mac's IP + port
API_KEY="${API_KEY:-1234}"                        # Print server API key
EVENT_ID="${EVENT_ID:-tLq7vbvees1E46fcb8BpE}"    # Your event ID
```

### Override defaults:
```bash
API_URL=http://YOUR_MAC_IP:3000 EVENT_ID=YOUR_EVENT_ID /tmp/friendlypos_server.sh
```

### Find your Event ID:
- From the URL: `http://localhost:3000/dashboard/TEAM/events/SLUG` → check the event in database
- Or from the API response when creating events

## API Endpoints

### Poll for jobs
```
GET /api/print-server/events/{eventId}/jobs?mark_as_printing=true
Header: x-api-key: {API_KEY}
```

### Mark job complete
```
POST /api/print-server/jobs/{jobId}/complete
Header: x-api-key: {API_KEY}
```

### Mark job failed
```
POST /api/print-server/jobs/{jobId}/fail
Header: x-api-key: {API_KEY}
Body: {"errorMessage": "..."}
```

## Running Crouton-Sales

```bash
cd /path/to/crouton-sales
HOST=0.0.0.0 pnpm dev
```

This makes the server listen on all interfaces, not just localhost.

## Troubleshooting

### Test connectivity from router:
```bash
# Check if Mac is reachable
ping 192.168.1.214

# Test API
curl -s -H "x-api-key: 1234" "http://192.168.1.214:3000/api/print-server/events/YOUR_EVENT_ID/jobs"
```

### Test printer from router:
```bash
# Check printer is reachable
nc -zv 192.168.1.100 9100

# Send test data
echo "Test print" | nc 192.168.1.100 9100
```

### Check script output:
The script prints status messages:
```
02:15:08 Crouton print spooler started
  API_URL: http://192.168.1.214:3000
  EVENT_ID: tLq7vbvees1E46fcb8BpE
02:15:10 Processing job ABC123 to 192.168.1.100
02:15:10 Job ABC123 sent to 192.168.1.100
```

### Common Issues

1. **No jobs found**: Check EVENT_ID matches your event
2. **Connection refused**: Ensure crouton-sales is running with `HOST=0.0.0.0`
3. **Jobs fetch but don't process**: JSON parsing issue - ensure script is up to date
4. **Printer timeout**: Check printer IP and ensure it's powered on

## Auto-Start on Boot

```bash
# Create init script
cat > /etc/init.d/printserver << 'EOF'
#!/bin/sh /etc/rc.common
START=99
STOP=10

start() {
    # Copy from persistent storage (tmp is cleared on reboot)
    cp /root/friendlypos_server.sh /tmp/friendlypos_server.sh 2>/dev/null
    chmod +x /tmp/friendlypos_server.sh
    /tmp/friendlypos_server.sh &
}

stop() {
    killall sh 2>/dev/null
}
EOF

chmod +x /etc/init.d/printserver
/etc/init.d/printserver enable

# Also copy script to persistent storage
cp /tmp/friendlypos_server.sh /root/friendlypos_server.sh
```

## Printer Setup

The Epson TM-m30 thermal printer:
- Default port: 9100 (raw TCP)
- Prints IP address slip on power-on
- Configure static IP via printer's web interface (access at printer's IP in browser)
