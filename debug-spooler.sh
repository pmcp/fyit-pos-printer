#!/bin/sh

API_KEY="d5a8262b7cfd8f46e599b36c584bb1ec16f28436680ddaa53f700e6d8a1765fa"

echo "=== DEBUG SPOOLER ==="
echo "Fetching jobs..."

RESPONSE=$(curl -s -m 5 -k -H "x-api-key: $API_KEY" https://friendlypos.vercel.app/api/print-queue 2>/dev/null)

echo "Raw response:"
echo "$RESPONSE"
echo ""

echo "All job IDs found (old method):"
echo "$RESPONSE" | sed -n 's/.*"id":"\([^"]*\)".*/\1/p'
echo ""

echo "All job IDs found (new method):"
echo "$RESPONSE" | grep -o '"id":"[^"]*"' | sed 's/"id":"\([^"]*\)"/\1/g'
echo ""

echo "Job count:"
echo "$RESPONSE" | sed -n 's/.*"id":"\([^"]*\)".*/\1/p' | wc -l
echo ""

echo "Processing each job:"
JOBLIST="/tmp/debug_jobs.txt"
echo "$RESPONSE" | sed -n 's/.*"id":"\([^"]*\)".*/\1/p' > "$JOBLIST"

JOB_NUM=1
while IFS= read -r JOB_ID; do
    if [ ! -z "$JOB_ID" ]; then
        echo "Job $JOB_NUM: ID=$JOB_ID"
        
        # Extract printer IP for this job
        JOB_PRINTER_IP=$(echo "$RESPONSE" | sed -n "s/.*\"id\":\"$JOB_ID\"[^}]*\"printer_ip\":\"\([^\"]*\)\".*/\1/p")
        echo "  Printer IP: $JOB_PRINTER_IP"
        
        JOB_NUM=$((JOB_NUM + 1))
    fi
done < "$JOBLIST"

rm -f "$JOBLIST"
echo "=== END DEBUG ==="