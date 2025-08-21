# Teltonika RUT956 Print Server Setup

## Installation on Router

1. Copy the script to the router:
```bash
scp teltonika-print-server.sh root@192.168.1.1:/tmp/friendlypos_server.sh
```

2. SSH into the router:
```bash
ssh root@192.168.1.1
```

3. Make it executable:
```bash
chmod +x /tmp/friendlypos_server.sh
```

4. Create init.d service (optional, for auto-start):
```bash
cat > /etc/init.d/printserver << 'EOF'
#!/bin/sh /etc/rc.common
START=99
STOP=10

start() {
    /tmp/friendlypos_server.sh &
}

stop() {
    killall friendlypos_server.sh
}
EOF

chmod +x /etc/init.d/printserver
/etc/init.d/printserver enable
/etc/init.d/printserver start
```

5. Monitor logs:
```bash
tail -f /tmp/printserver.log
```

## Configuration

- **API URL**: https://friendlypos.vercel.app/api/print-queue
- **API Key**: Set in the script
- **Printer IP**: 192.168.1.100 (port 9100)
- **Poll Interval**: 2 seconds
- **After Print Delay**: 10 seconds (prevents duplicates)

## API Endpoints Required

### 1. GET /api/print-queue
Returns array of pending orders

### 2. POST /api/print-confirm
Confirms print status:
```json
{
  "order_id": "123",
  "status": "printed"
}
```

## Troubleshooting

1. Check connectivity:
```bash
ping 8.8.8.8
curl https://friendlypos.vercel.app
```

2. Check printer:
```bash
nc -zv 192.168.1.100 9100
```

3. View logs:
```bash
cat /tmp/printserver.log
```

4. Test API manually:
```bash
curl -H "X-API-Key: your-key" https://friendlypos.vercel.app/api/print-queue
```