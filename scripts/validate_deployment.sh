#!/bin/bash

echo "FriendlyPOS Print Server - Deployment Validation"
echo "================================================"
echo ""

PASS_COUNT=0
FAIL_COUNT=0
TARGET=${1:-localhost}

pass() {
    echo "  ✓ $1"
    ((PASS_COUNT++))
}

fail() {
    echo "  ✗ $1"
    ((FAIL_COUNT++))
}

check_command() {
    if command -v $1 &> /dev/null; then
        pass "$1 is installed"
    else
        fail "$1 is not installed"
    fi
}

echo "1. System Requirements"
echo "----------------------"

check_command python3
check_command git

if [ -f /etc/openwrt_release ]; then
    echo "  ℹ Running on OpenWrt"
else
    echo "  ℹ Not running on OpenWrt (development environment)"
fi

echo ""
echo "2. File Structure"
echo "-----------------"

FILES=(
    "print_server.py"
    "config.env.example"
    "requirements.txt"
    "README.md"
)

for file in "${FILES[@]}"; do
    if [ -f "$file" ]; then
        pass "$file exists"
    else
        fail "$file missing"
    fi
done

echo ""
echo "3. Configuration"
echo "----------------"

if [ -f "config.env" ]; then
    pass "config.env exists"
    
    source config.env
    
    if [ -n "$API_URL" ] && [ "$API_URL" != "https://your-app.vercel.app" ]; then
        pass "API_URL configured"
    else
        fail "API_URL not configured"
    fi
    
    if [ -n "$API_KEY" ] && [ "$API_KEY" != "your-api-key-here" ]; then
        pass "API_KEY configured"
    else
        fail "API_KEY not configured"
    fi
    
    if [ -n "$LOCATION_ID" ]; then
        pass "LOCATION_ID configured"
    else
        fail "LOCATION_ID not configured"
    fi
else
    fail "config.env not found"
fi

echo ""
echo "4. Python Environment"
echo "--------------------"

if [ -d "venv" ]; then
    pass "Virtual environment exists"
    
    if [ -f "venv/bin/python" ]; then
        PYTHON_VERSION=$(venv/bin/python --version 2>&1)
        pass "Python in venv: $PYTHON_VERSION"
    fi
else
    echo "  ℹ No virtual environment (OK for production)"
fi

echo ""
echo "5. Network Connectivity"
echo "-----------------------"

if ping -c 1 google.com &> /dev/null; then
    pass "Internet connection working"
else
    fail "No internet connection"
fi

if [ -n "$API_URL" ] && [ "$API_URL" != "https://your-app.vercel.app" ]; then
    API_HOST=$(echo $API_URL | sed -e 's|^[^/]*//||' -e 's|/.*$||')
    if ping -c 1 $API_HOST &> /dev/null 2>&1; then
        pass "Can reach API host: $API_HOST"
    else
        echo "  ⚠ Cannot ping API host (may still work)"
    fi
fi

echo ""
echo "6. Printer Connectivity"
echo "-----------------------"

check_printer() {
    local name=$1
    local address=$2
    
    if [ -z "$address" ] || [ "$address" == ":" ]; then
        return
    fi
    
    IFS=':' read -r host port <<< "$address"
    
    if timeout 2 bash -c "echo > /dev/tcp/$host/$port" 2>/dev/null; then
        pass "Printer $name reachable at $host:$port"
    else
        fail "Printer $name not reachable at $host:$port"
    fi
}

if [ -f "config.env" ]; then
    source config.env
    
    check_printer "MAIN" "$PRINTER_MAIN"
    check_printer "KITCHEN" "$PRINTER_KITCHEN"
    check_printer "BAR" "$PRINTER_BAR"
else
    echo "  ⚠ Cannot check printers without config.env"
fi

echo ""
echo "7. Service Status (Production)"
echo "------------------------------"

if [ "$TARGET" != "localhost" ]; then
    if ssh $TARGET "[ -f /etc/init.d/print_server ]" 2>/dev/null; then
        pass "Service script installed on $TARGET"
        
        STATUS=$(ssh $TARGET "/etc/init.d/print_server status" 2>/dev/null)
        if [[ $STATUS == *"running"* ]]; then
            pass "Service is running"
        else
            fail "Service is not running"
        fi
    else
        fail "Service script not found on $TARGET"
    fi
else
    echo "  ℹ Skipping service check (local environment)"
fi

echo ""
echo "8. Test Suite"
echo "-------------"

if [ -f "venv/bin/python" ]; then
    echo "  Running unit tests..."
    if venv/bin/python -m pytest tests/test_server.py -q 2>/dev/null; then
        pass "Unit tests passed"
    else
        fail "Unit tests failed"
    fi
else
    echo "  ⚠ Cannot run tests without virtual environment"
fi

echo ""
echo "9. Memory Check"
echo "---------------"

if [ "$TARGET" != "localhost" ] && [ -n "$TARGET" ]; then
    MEM_INFO=$(ssh $TARGET "free -m" 2>/dev/null | grep Mem)
    if [ -n "$MEM_INFO" ]; then
        TOTAL_MEM=$(echo $MEM_INFO | awk '{print $2}')
        USED_MEM=$(echo $MEM_INFO | awk '{print $3}')
        FREE_MEM=$(echo $MEM_INFO | awk '{print $4}')
        echo "  ℹ Memory on $TARGET: ${USED_MEM}MB used / ${TOTAL_MEM}MB total"
        
        if [ $FREE_MEM -gt 10 ]; then
            pass "Sufficient free memory (${FREE_MEM}MB)"
        else
            fail "Low memory warning (${FREE_MEM}MB free)"
        fi
    fi
else
    MEM_AVAILABLE=$(vm_stat | grep "Pages free" | awk '{print $3}' | sed 's/\.//')
    if [ -n "$MEM_AVAILABLE" ]; then
        MEM_MB=$((MEM_AVAILABLE * 4096 / 1024 / 1024))
        echo "  ℹ Available memory: ~${MEM_MB}MB"
    fi
fi

echo ""
echo "10. Quick Functionality Test"
echo "----------------------------"

if [ -f "print_server.py" ]; then
    echo "  Testing print server import..."
    if python3 -c "import print_server" 2>/dev/null; then
        pass "Print server module loads correctly"
    else
        fail "Print server module has errors"
    fi
fi

echo ""
echo "========================================"
echo "Validation Summary"
echo "========================================"
echo "  Passed: $PASS_COUNT"
echo "  Failed: $FAIL_COUNT"
echo ""

if [ $FAIL_COUNT -eq 0 ]; then
    echo "✓ System is ready for deployment!"
    exit 0
else
    echo "✗ Issues found. Please fix before deploying."
    exit 1
fi