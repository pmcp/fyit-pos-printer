#!/bin/bash

echo "FriendlyPOS Print Server - Development Mode"
echo "==========================================="

if [ -f config.env ]; then
    echo "Loading configuration from config.env..."
    set -a
    source config.env
    set +a
else
    echo "Warning: config.env not found. Using defaults."
    echo "Create one by copying config.env.example:"
    echo "  cp config.env.example config.env"
    echo ""
fi

export DEV_MODE=1
export DEBUG_LEVEL=${DEBUG_LEVEL:-DEBUG}

if [ -d venv ]; then
    echo "Activating virtual environment..."
    source venv/bin/activate
else
    echo "Virtual environment not found."
    echo "Run ./setup.sh first to create it."
    exit 1
fi

LOG_FILE="${LOG_FILE:-/tmp/print_server_dev.log}"
echo "Logs will be written to: $LOG_FILE"
echo "Press Ctrl+C to stop the server"
echo ""

python3 print_server.py

deactivate 2>/dev/null

echo ""
echo "Server stopped."