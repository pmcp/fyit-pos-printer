#!/bin/bash

echo "Setting up local development environment..."
echo "=========================================="

cd "$(dirname "$0")/.." || exit 1

if ! command -v python3 &> /dev/null; then
    echo "Error: Python 3 is not installed."
    echo "Please install Python 3.7 or higher and try again."
    exit 1
fi

PYTHON_VERSION=$(python3 -c 'import sys; print(".".join(map(str, sys.version_info[:2])))')
echo "Found Python $PYTHON_VERSION"

if [ -d venv ]; then
    echo "Virtual environment already exists. Removing old environment..."
    rm -rf venv
fi

echo "Creating virtual environment..."
python3 -m venv venv

echo "Activating virtual environment..."
source venv/bin/activate

echo "Upgrading pip..."
pip install --upgrade pip

echo "Installing development dependencies..."
pip install pytest pytest-asyncio

if [ ! -f config.env ]; then
    echo "Creating config.env from template..."
    cp config.env.example config.env
    echo ""
    echo "IMPORTANT: Edit config.env with your API credentials:"
    echo "  - API_URL: Your FriendlyPOS API endpoint"
    echo "  - API_KEY: Your API authentication key"
    echo "  - LOCATION_ID: Your location identifier"
    echo "  - PRINTER_*: Your printer IP addresses"
else
    echo "config.env already exists, skipping..."
fi

chmod +x print_server.py
chmod +x run_dev.sh
chmod +x setup.sh

echo ""
echo "Development environment setup complete!"
echo ""
echo "Next steps:"
echo "1. Edit config.env with your settings"
echo "2. Run the server with: ./run_dev.sh"
echo "3. Or activate venv manually: source venv/bin/activate"
echo ""
echo "To run tests:"
echo "  source venv/bin/activate"
echo "  python -m pytest tests/"