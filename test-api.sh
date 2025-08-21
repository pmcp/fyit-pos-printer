#!/bin/sh
# Test API connectivity from Teltonika

API_URL="https://friendlypos.vercel.app/api/print-queue"
API_KEY="d5a8262b7cfd8f46e599b36c584bb1ec16f28436680ddaa53f700e6d8a1765fa"

echo "=== Testing API Connection ==="
echo "URL: $API_URL"
echo ""

# Test 1: Basic connectivity
echo "Test 1: Ping friendlypos.vercel.app"
ping -c 2 friendlypos.vercel.app

echo ""
echo "Test 2: DNS resolution"
nslookup friendlypos.vercel.app

echo ""
echo "Test 3: curl with verbose output"
curl -v -H "X-API-Key: $API_KEY" "$API_URL" 2>&1 | head -50

echo ""
echo "Test 4: wget as alternative"
wget -O- --header="X-API-Key: $API_KEY" "$API_URL" 2>&1 | head -20

echo ""
echo "Test 5: Check if SSL is the issue"
curl -k -s -H "X-API-Key: $API_KEY" "$API_URL" | head -100

echo ""
echo "Test 6: Check network interfaces"
ifconfig | grep -A2 "inet "

echo ""
echo "Test 7: Check default route"
route -n | head -5