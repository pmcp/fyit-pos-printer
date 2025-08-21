# Teltonika Print Server Fix - Deployment Guide

## Problem Summary
The Teltonika RUT956 router was receiving valid Base64-encoded ESC/POS data from the API but printing gibberish. The issue was that the shell script's Base64 decoding and binary data handling was corrupting the ESC/POS commands.

## Solution Overview
Created a binary-safe version of the print server script that:
1. Decodes Base64 to a temporary binary file (preserves binary integrity)
2. Verifies the decoded ESC/POS data is valid
3. Uses `dd` or `cat` to send binary data to printer without corruption
4. Falls back to simple text printing if binary mode fails

## Files Created

### 1. `teltonika-print-fixed.sh`
The main fixed print server script with:
- Multiple Base64 decoding methods (base64, python, awk)
- Binary-safe file handling
- ESC/POS validation
- Debug mode for troubleshooting
- Fallback text mode

### 2. `base64_decoder.py`
Simple Python helper script for Base64 decoding that works with Python 2 or 3.

### 3. `test_fixed_decoding.sh`
Test script to verify Base64 decoding works correctly on the target system.

## Deployment Instructions

### Step 1: Test Locally
```bash
# Make scripts executable
chmod +x teltonika-print-fixed.sh
chmod +x test_fixed_decoding.sh
chmod +x base64_decoder.py

# Run the test script
./test_fixed_decoding.sh

# You should see:
# ✓ Valid ESC/POS header (1B 40)
# File size: 346 bytes
```

### Step 2: Deploy to Teltonika Router

```bash
# Copy the main script to the router
scp teltonika-print-fixed.sh root@192.168.1.1:/root/print_server_fixed.sh

# Optional: Copy Python helper if Python is available on router
scp base64_decoder.py root@192.168.1.1:/root/base64_decoder.py

# SSH into the router
ssh root@192.168.1.1

# Make executable on the router
chmod +x /root/print_server_fixed.sh
chmod +x /root/base64_decoder.py  # if copied

# Stop the old script if running
killall teltonika-print-server.sh 2>/dev/null

# Start the new script
nohup /root/print_server_fixed.sh &

# Monitor the logs
tail -f /tmp/printserver.log
```

### Step 3: Verify Operation

1. Check the log file shows proper initialization:
```bash
tail -f /tmp/printserver.log
# Should show:
# Print Server Started (Binary Safe Fixed Version)
# Valid ESC/POS data (starts with ESC @)
# Order printed successfully
```

2. If debug mode is enabled, check binary files:
```bash
# Check saved binary files (debug mode)
od -An -tx1 -N 20 /tmp/order_*.bin
# Should start with: 1b 40 (ESC @)
```

### Step 4: Troubleshooting

#### If Base64 decoding fails:
1. Check which method works on your router:
```bash
# Test base64 command
echo "SGVsbG8=" | base64 -d  # Should output: Hello

# Test Python
python -c "import base64; print(base64.b64decode('SGVsbG8='))"
```

2. The script will automatically try multiple methods and log which one works.

#### If printing still shows gibberish:
1. Enable debug mode in the script (DEBUG_MODE=1)
2. Check the binary file is created correctly:
```bash
ls -la /tmp/order_*.bin
od -An -tx1 -N 50 /tmp/order_*.bin
```

3. Test direct printing with the saved binary file:
```bash
cat /tmp/order_*.bin | nc 192.168.1.100 9100
```

#### If the printer doesn't respond:
1. Test basic connectivity:
```bash
echo "TEST" | nc 192.168.1.100 9100
```

2. Verify ESC/POS commands work:
```bash
printf '\x1b\x40TEST\n\x1d\x56\x00' | nc 192.168.1.100 9100
```

### Step 5: Make Permanent (Optional)

To ensure the script starts on router boot:

```bash
# On the router, add to startup script
echo "/root/print_server_fixed.sh &" >> /etc/rc.local

# Or create a service file if using init.d
cat > /etc/init.d/printserver << 'EOF'
#!/bin/sh /etc/rc.common
START=99
start() {
    /root/print_server_fixed.sh &
}
stop() {
    killall print_server_fixed.sh
}
EOF

chmod +x /etc/init.d/printserver
/etc/init.d/printserver enable
```

## Key Improvements

1. **Binary Safety**: Decodes to file first, preserving binary integrity
2. **Multiple Decoders**: Tries base64, Python, and awk methods
3. **Validation**: Verifies ESC/POS header before sending
4. **Debug Mode**: Keeps binary files for inspection
5. **Fallback**: Text mode if binary fails
6. **Logging**: Detailed logging of each step

## Expected Behavior

With the fix deployed, you should see:
- Clean, properly formatted receipts
- Bold text where expected
- Proper alignment
- Automatic paper cutting
- No more gibberish characters

## Notes

- The script uses -k flag with curl to bypass SSL verification (required for Vercel)
- Default polling interval is 2 seconds
- Binary files are kept in debug mode for troubleshooting
- The script handles both "printer_ip" and "ip_address" field names from the API