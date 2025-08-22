#!/bin/sh
# Diagnose API connectivity issues on Teltonika

API_URL="https://friendlypos.vercel.app/api/print-queue"
API_KEY="d5a8262b7cfd8f46e599b36c584bb1ec16f28436680ddaa53f700e6d8a1765fa"

echo "=== API Connectivity Diagnosis ==="
echo ""

echo "Test 1: Basic connectivity to Vercel"
echo "-------------------------------------"
ping -c 3 friendlypos.vercel.app

echo ""
echo "Test 2: DNS resolution"
echo "----------------------"
nslookup friendlypos.vercel.app

echo ""
echo "Test 3: curl with verbose output"
echo "---------------------------------"
curl -kv -H "X-API-Key: $API_KEY" "$API_URL" 2>&1 | head -30

echo ""
echo "Test 4: curl with timing info"
echo "------------------------------"
curl -k -w "\nTime_namelookup: %{time_namelookup}\nTime_connect: %{time_connect}\nTime_starttransfer: %{time_starttransfer}\nTime_total: %{time_total}\n" \
     -H "X-API-Key: $API_KEY" "$API_URL" -o /dev/null -s

echo ""
echo "Test 5: Multiple rapid requests"
echo "--------------------------------"
for i in 1 2 3 4 5; do
    echo -n "Request $i: "
    if curl -k -s -m 5 -H "X-API-Key: $API_KEY" "$API_URL" > /dev/null 2>&1; then
        echo "SUCCESS"
    else
        echo "FAILED (exit code: $?)"
    fi
    sleep 1
done

echo ""
echo "Test 6: Check SSL/TLS without -k flag"
echo "--------------------------------------"
echo "With -k (skip SSL verification):"
time curl -k -s -H "X-API-Key: $API_KEY" "$API_URL" > /dev/null 2>&1 && echo "SUCCESS" || echo "FAILED"

echo ""
echo "Without -k (verify SSL):"
time curl -s -H "X-API-Key: $API_KEY" "$API_URL" > /dev/null 2>&1 && echo "SUCCESS" || echo "FAILED"

echo ""
echo "Test 7: Memory and system resources"
echo "------------------------------------"
free
echo ""
df -h /tmp
echo ""
ps | wc -l
echo "processes running"

echo ""
echo "Test 8: Network interface status"
echo "---------------------------------"
ifconfig | grep -A1 "inet addr"

echo ""
echo "=== Diagnosis Complete ==="