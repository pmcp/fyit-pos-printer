#!/bin/sh

# Test script to simulate multi-job processing

# Mock API response with 2 jobs
RESPONSE='[{"id":"100","queue_id":100,"printer_ip":"192.168.1.100","print_data":"test1"},{"id":"101","queue_id":101,"printer_ip":"192.168.1.70","print_data":"test2"}]'

echo "=== MULTI-JOB TEST ==="
echo "Simulated API response with 2 jobs:"
echo "$RESPONSE"
echo ""

echo "Job IDs extraction test:"
echo "Method 1 (old): $(echo "$RESPONSE" | sed -n 's/.*"id":"\([^"]*\)".*/\1/p')"
echo "Method 2 (new): $(echo "$RESPONSE" | grep -o '"id":"[^"]*"' | sed 's/"id":"\([^"]*\)"/\1/g')"
echo ""

echo "Processing simulation:"
JOBLIST="/tmp/test_jobs.txt"
echo "$RESPONSE" | grep -o '"id":"[^"]*"' | sed 's/"id":"\([^"]*\)"/\1/g' > "$JOBLIST"

JOB_NUM=1
while IFS= read -r JOB_ID; do
    if [ ! -z "$JOB_ID" ]; then
        JOB_PRINTER_IP=$(echo "$RESPONSE" | sed -n "s/.*\"id\":\"$JOB_ID\"[^}]*\"printer_ip\":\"\([^\"]*\)\".*/\1/p")
        echo "Job $JOB_NUM: ID=$JOB_ID, Printer=$JOB_PRINTER_IP"
        JOB_NUM=$((JOB_NUM + 1))
    fi
done < "$JOBLIST"

rm -f "$JOBLIST"
echo "=== END TEST ==="