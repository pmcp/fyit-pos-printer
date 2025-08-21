# FriendlyPOS Print Server Implementation Plan

## Project Overview
Create a lightweight Python-based print server that bridges the cloud-based FriendlyPOS web app with local thermal printers. The server will run on a Teltonika RUT956 router (OpenWrt) and handle order printing with event-specific customization.

## Repository Structure

### Should this be a new repository?
**Yes** - Create a separate repository: `friendlypos-print-server`

**Reasons:**
- Different deployment target (embedded router vs cloud)
- Different technology stack (Python vs TypeScript/Nuxt)
- Independent versioning and releases
- Cleaner separation of concerns
- Easier to maintain and debug

## Phase 1: Repository Setup (Day 1)

### 1.1 Create New Repository
```bash
# Create new repository
mkdir friendlypos-print-server
cd friendlypos-print-server
git init

# Create initial structure
touch README.md
touch .gitignore
touch requirements.txt
touch config.env.example
```

### 1.2 Initial File Structure
```
friendlypos-print-server/
├── print_server.py          # Main application
├── setup.sh                 # Universal installer
├── run_dev.sh              # Development runner
├── config.env.example      # Configuration template
├── requirements.txt        # Python dependencies
├── .gitignore             # Git ignore rules
├── README.md              # Documentation
├── scripts/               # Utility scripts
│   ├── install_openwrt.sh
│   ├── setup_dev.sh
│   ├── deploy.sh
│   └── test_printer.py
├── init.d/                # OpenWrt service files
│   └── print_server
└── tests/                 # Test files
    ├── test_server.py
    └── mock_printer.py
```

### 1.3 Core Files to Create First

1. **`.gitignore`** - Prevent committing sensitive files
2. **`config.env.example`** - Configuration template
3. **`print_server.py`** - Main application (start with basic structure)
4. **`README.md`** - Basic documentation

## Phase 2: Core Print Server Development (Day 1-2)

### 2.1 Basic Print Server (`print_server.py`)
Start with minimal viable functionality:

```python
#!/usr/bin/env python3
"""
FriendlyPOS Print Server - Teltonika RUT956 Edition
"""

import json
import socket
import time
import urllib.request
import sys
import os
import logging

# Configuration from environment
CONFIG = {
    'api_url': os.getenv('API_URL', 'https://your-app.vercel.app'),
    'api_key': os.getenv('API_KEY', ''),
    'location_id': os.getenv('LOCATION_ID', '1'),
    'poll_interval': int(os.getenv('POLL_INTERVAL', '2'))
}
```

### 2.2 Essential Classes to Implement
1. **`SimplePrinter`** - Basic ESC/POS communication
   - `connect()` - Establish TCP connection
   - `send()` - Send raw data to printer
   - `print_order()` - Format and print order
   - `disconnect()` - Close connection

2. **`PrintServer`** - Main application logic
   - `make_api_request()` - HTTP communication with web app
   - `load_printers()` - Get printer configurations
   - `load_event_settings()` - Get event-specific settings
   - `poll_for_jobs()` - Check for pending orders
   - `process_order()` - Handle order printing
   - `run()` - Main loop

### 2.3 API Endpoints to Integrate
Your print server needs to call these FriendlyPOS API endpoints:

```
GET  /api/print-queue        # Get pending orders
GET  /api/printers          # Get printer configurations  
GET  /api/settings          # Get event-specific settings
PATCH /api/orders/:id/status # Update order status
```

## Phase 3: Development Environment Setup (Day 2)

### 3.1 Local Development Setup Script (`scripts/setup_dev.sh`)
```bash
#!/bin/bash
# Create virtual environment
python3 -m venv venv
source venv/bin/activate

# Install dev dependencies
pip install pytest pytest-asyncio
```

### 3.2 Development Runner (`run_dev.sh`)
Create a script that:
- Loads configuration from `config.env`
- Sets `DEV_MODE=1` for local testing
- Runs with debug logging
- Auto-restarts on file changes (optional)

### 3.3 Mock Testing Tools
1. **Printer Emulator** (`tests/mock_printer.py`)
   - Listens on port 9100
   - Logs received data
   - Responds with success status

2. **Test Script** (`scripts/test_printer.py`)
   - Tests real printer connectivity
   - Sends test print job

## Phase 4: OpenWrt/Teltonika Integration (Day 3)

### 4.1 OpenWrt Installation Script (`scripts/install_openwrt.sh`)
```bash
#!/bin/sh
# Install Python packages
opkg update
opkg install python3-light python3-logging python3-urllib

# Create directories
mkdir -p /usr/local/friendlypos

# Install init.d script
cp init.d/print_server /etc/init.d/
chmod +x /etc/init.d/print_server
```

### 4.2 Init.d Service Script (`init.d/print_server`)
- Use procd for process management
- Load configuration from `/usr/local/friendlypos/config.env`
- Enable auto-restart on crash
- Log to `/tmp/print_server.log` (RAM, not flash)

### 4.3 Deployment Script (`scripts/deploy.sh`)
```bash
#!/bin/bash
TARGET=${1:-root@192.168.1.1}
ssh $TARGET "cd /usr/local/friendlypos && git pull"
ssh $TARGET "/etc/init.d/print_server restart"
```

## Phase 5: Testing & Validation (Day 3-4)

### 5.1 Unit Tests (`tests/test_server.py`)
Test critical functions:
- API request handling
- Order data parsing
- Printer connection logic
- Error handling

### 5.2 Integration Testing
1. **Local Testing with Mock API**
   - Create mock API server
   - Test full print flow

2. **Router Testing**
   - Deploy to actual Teltonika
   - Test with real printers
   - Verify auto-start on boot

### 5.3 Test Checklist
- [ ] Print server starts on boot
- [ ] Connects to API successfully
- [ ] Loads printer configurations
- [ ] Loads event settings
- [ ] Processes orders correctly
- [ ] Handles printer offline gracefully
- [ ] Updates order status properly
- [ ] Logs are written to `/tmp`
- [ ] Memory usage stays under 10MB

## Phase 6: Documentation (Day 4)

### 6.1 README.md Structure
```markdown
# FriendlyPOS Print Server

## Quick Start
### Development
### Production (Teltonika Router)

## Configuration
### Required Settings
### Optional Settings

## API Integration
### Endpoints Used
### Authentication

## Troubleshooting
### Common Issues
### Debug Commands

## Architecture
### How It Works
### Data Flow
```

### 6.2 Inline Code Documentation
- Add docstrings to all functions
- Include type hints where helpful
- Comment complex logic

## Phase 7: Production Deployment (Day 5)

### 7.1 Pre-Deployment Checklist
- [ ] Remove all debug print statements
- [ ] Set appropriate log levels
- [ ] Test on actual Teltonika hardware
- [ ] Verify network connectivity (LAN for printers, WAN for API)
- [ ] Configure firewall if needed

### 7.2 Deployment Steps
1. **Push to GitHub**
   ```bash
   git add .
   git commit -m "Initial production release"
   git push origin main
   git tag v1.0.0
   git push --tags
   ```

2. **Deploy to Router**
   ```bash
   ssh root@192.168.1.1
   cd /usr/local
   git clone https://github.com/yourusername/friendlypos-print-server.git friendlypos
   cd friendlypos
   ./setup.sh
   cp config.env.example config.env
   vi config.env  # Add production credentials
   /etc/init.d/print_server enable
   /etc/init.d/print_server start
   ```

3. **Verify Operation**
   ```bash
   # Check status
   /etc/init.d/print_server status
   
   # Monitor logs
   tail -f /tmp/print_server.log
   
   # Test print
   python3 scripts/test_printer.py 192.168.1.100
   ```

## Implementation Priority Order

### Must Have (MVP)
1. ✅ Basic print server that polls API
2. ✅ ESC/POS printer communication
3. ✅ Order status updates
4. ✅ Event settings integration
5. ✅ OpenWrt init.d script
6. ✅ Basic error handling

### Should Have
1. ⏳ Printer health monitoring
2. ⏳ Retry mechanism for failed prints
3. ⏳ Multiple printer support
4. ⏳ Deployment automation

### Nice to Have
1. ⏳ Web UI for router (LuCI integration)
2. ⏳ Metrics and statistics
3. ⏳ Automatic updates via git
4. ⏳ Advanced queue management

## Key Decisions for Claude Code

### 1. Technology Choices
- **Language**: Python 3 (lightweight, good hardware support)
- **Dependencies**: Minimal - only standard library for production
- **Logging**: To `/tmp` to avoid flash wear
- **Service**: Use OpenWrt's procd for management

### 2. Architecture Decisions
- **Polling vs WebSockets**: Use polling (simpler, more reliable)
- **State Management**: Stateless - all state in web app
- **Error Recovery**: Simple retry with exponential backoff
- **Configuration**: Environment variables from file

### 3. Development Workflow
- **Version Control**: Git with GitHub
- **Testing**: Local development with mock printer
- **Deployment**: Git pull on router or rsync
- **Updates**: Manual or automated via cron

## Success Criteria

### Functional Requirements
- [ ] Orders print within 3 seconds of creation
- [ ] Supports multiple printers per location
- [ ] Handles network interruptions gracefully
- [ ] Uses event-specific receipt settings
- [ ] Runs reliably for weeks without intervention

### Performance Requirements
- [ ] Uses less than 10MB RAM
- [ ] CPU usage under 5% average
- [ ] Startup time under 2 seconds
- [ ] Can handle 100+ orders per hour

### Operational Requirements
- [ ] Starts automatically on router boot
- [ ] Logs are accessible and useful
- [ ] Can be updated without router access
- [ ] Configuration changes don't require restart

## Notes for Claude Code

1. **Start Simple**: Get basic printing working first, then add features
2. **Test Early**: Use mock printer for development to avoid wasting paper
3. **Handle Errors**: Network and printer issues are common - handle gracefully
4. **Keep It Light**: Router has limited resources - optimize for memory/CPU
5. **Document Everything**: Future you will thank current you

## Repository Link Structure

### Main Repository (Web App)
`github.com/yourusername/friendlypos` - Nuxt.js web application

### Print Server Repository (New)
`github.com/yourusername/friendlypos-print-server` - Python print server

### Relationship
- Print server consumes APIs from web app
- Separate deployment cycles
- Independent versioning

## Getting Started Commands for Claude Code

```bash
# 1. Create new repository
mkdir friendlypos-print-server
cd friendlypos-print-server
git init

# 2. Copy provided files from this plan
# (Use the artifacts from our conversation)

# 3. Set up development environment
chmod +x setup.sh
./setup.sh

# 4. Configure
cp config.env.example config.env
# Edit config.env with your API details

# 5. Run locally
./run_dev.sh

# 6. Test
python tests/test_server.py

# 7. Commit
git add .
git commit -m "Initial implementation"

# 8. Deploy to router
./scripts/deploy.sh root@192.168.1.1
```

This plan provides a clear, step-by-step approach to implementing the print server with all necessary components and considerations for the Teltonika RUT956 router environment.
