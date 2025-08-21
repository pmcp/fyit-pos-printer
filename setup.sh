#!/bin/bash

echo "FriendlyPOS Print Server - Universal Installer"
echo "=============================================="

detect_platform() {
    if [ -f /etc/openwrt_release ]; then
        echo "openwrt"
    elif [ -f /etc/debian_version ]; then
        echo "debian"
    elif [ -f /etc/redhat-release ]; then
        echo "redhat"
    elif [ "$(uname)" == "Darwin" ]; then
        echo "macos"
    else
        echo "unknown"
    fi
}

PLATFORM=$(detect_platform)
echo "Detected platform: $PLATFORM"

case $PLATFORM in
    openwrt)
        echo "Installing for OpenWrt/Teltonika router..."
        
        opkg update
        opkg install python3-light python3-logging
        
        INSTALL_DIR="/usr/local/friendlypos"
        mkdir -p $INSTALL_DIR
        
        cp print_server.py $INSTALL_DIR/
        cp config.env.example $INSTALL_DIR/
        
        if [ -f init.d/print_server ]; then
            cp init.d/print_server /etc/init.d/
            chmod +x /etc/init.d/print_server
            echo "Service script installed to /etc/init.d/print_server"
        fi
        
        echo "Installation complete!"
        echo "Next steps:"
        echo "1. cd $INSTALL_DIR"
        echo "2. cp config.env.example config.env"
        echo "3. vi config.env  # Add your API credentials"
        echo "4. /etc/init.d/print_server enable"
        echo "5. /etc/init.d/print_server start"
        ;;
        
    debian|ubuntu)
        echo "Installing for Debian/Ubuntu..."
        
        if ! command -v python3 &> /dev/null; then
            echo "Python 3 not found, installing..."
            sudo apt-get update
            sudo apt-get install -y python3 python3-venv
        fi
        
        echo "Creating virtual environment..."
        python3 -m venv venv
        source venv/bin/activate
        
        if [ -f requirements.txt ]; then
            pip install -r requirements.txt
        fi
        
        echo "Installation complete!"
        echo "To run: ./run_dev.sh"
        ;;
        
    macos)
        echo "Installing for macOS..."
        
        if ! command -v python3 &> /dev/null; then
            echo "Python 3 not found. Please install Python 3 first:"
            echo "brew install python3"
            exit 1
        fi
        
        echo "Creating virtual environment..."
        python3 -m venv venv
        source venv/bin/activate
        
        if [ -f requirements.txt ]; then
            pip install -r requirements.txt
        fi
        
        echo "Installation complete!"
        echo "To run: ./run_dev.sh"
        ;;
        
    *)
        echo "Platform not directly supported. Manual installation required."
        echo ""
        echo "Manual installation steps:"
        echo "1. Ensure Python 3.7+ is installed"
        echo "2. Create virtual environment: python3 -m venv venv"
        echo "3. Activate venv: source venv/bin/activate"
        echo "4. Install dependencies: pip install -r requirements.txt"
        echo "5. Copy config.env.example to config.env"
        echo "6. Edit config.env with your settings"
        echo "7. Run: python3 print_server.py"
        exit 1
        ;;
esac

chmod +x print_server.py 2>/dev/null
chmod +x run_dev.sh 2>/dev/null
chmod +x scripts/*.sh 2>/dev/null

echo ""
echo "Setup complete!"