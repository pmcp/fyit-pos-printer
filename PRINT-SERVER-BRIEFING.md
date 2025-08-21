# Print Server Integration Briefing

## Overview
This system sends print jobs from a web API to thermal receipt printers via a Teltonika RUT956 router. The router polls the API for pending orders and forwards them to network-connected printers.

## Current Architecture

### 1. API Endpoint
- **URL**: `https://friendlypos.vercel.app/api/print-queue`
- **Method**: GET
- **Headers**: `X-API-Key: [api-key]`
- **Returns**: JSON array of pending orders

### 2. Router Script Location
- **File**: `/tmp/friendlypos_server.sh` on Teltonika router
- **Source**: `/Users/pmcp/Projects/fyit-pos-printer/teltonika-print-server.sh`

### 3. Current Data Flow
```
API (JSON) → Router (Parse) → Printer (ESC/POS)
```

## Current JSON Structure
```json
[
  {
    "id": "123",
    "printer_ip": "192.168.1.100",
    "items": [
      {"name": "Burger", "quantity": 2, "price": 12.50}
    ],
    "total": 29.50
  }
]
```

## Required Change: Add Server-Side Formatting

### Option 1: Base64 Encoded ESC/POS (RECOMMENDED)
Modify API to include pre-formatted receipt data:

```json
{
  "id": "123",
  "printer_ip": "192.168.1.100",
  "print_data": "G1tAG1thAR0hMEZSSUVORExZIFBPUw..."  // Base64 encoded ESC/POS
}
```

The router script already supports this - it checks for `print_data` field and if present:
1. Decodes from base64
2. Sends raw bytes directly to printer
3. No parsing or formatting needed

### Implementation Steps for API:

1. **Install ESC/POS library** :
   ```bash
   npm install node-thermal-printer
   ```

2. **Generate ESC/POS commands** for the receipt:
   ```javascript
   // Example with node-thermal-printer
   const printer = new ThermalPrinter({type: Types.EPSON});
   
   printer.alignCenter();
   printer.setTextDoubleHeight();
   printer.println('FRIENDLY POS');
   printer.setTextNormal();
   
   // Add order details
   order.items.forEach(item => {
     printer.leftRight(`${item.qty}x ${item.name}`, `$${item.price}`);
   });
   
   printer.drawLine();
   printer.println(`TOTAL: $${order.total}`);
   printer.cut();
   
   // Get buffer and encode to base64
   const commands = printer.getBuffer();
   const base64 = Buffer.from(commands).toString('base64');
   ```

3. **Add to API response**:
   ```javascript
   return {
     id: order.id,
     printer_ip: order.printer_ip || "192.168.1.100",
     print_data: base64,  // Add this field
     // Keep other fields for backwards compatibility
     items: order.items,
     total: order.total
   };
   ```

### Option 2: Structured Receipt Object
If you prefer human-readable API:

```json
{
  "id": "123",
  "printer_ip": "192.168.1.100",
  "receipt": {
    "header": {"text": "FRIENDLY POS", "size": "double", "align": "center"},
    "lines": [
      {"type": "item", "name": "Burger", "qty": 2, "price": 12.50},
      {"type": "separator"},
      {"type": "total", "value": 29.50}
    ],
    "footer": {"text": "Thank You!", "align": "center"}
  }
}
```

(Would require router script modification to parse this structure)

## ESC/POS Command Reference

Common commands for formatting:
```
Initialize: \x1B\x40
Bold: \x1B\x45\x01 (on) / \x1B\x45\x00 (off)
Underline: \x1B\x2D\x01 (on) / \x1B\x2D\x00 (off)
Center: \x1B\x61\x01
Left: \x1B\x61\x00
Right: \x1B\x61\x02
Double size: \x1D\x21\x30
Normal size: \x1D\x21\x00
Cut paper: \x1D\x56\x00
```

## Testing

1. **Generate test receipt**:
   ```javascript
   const testData = generateReceipt(testOrder);
   console.log(testData); // Base64 string
   ```

2. **Test locally** (if you have printer access):
   ```bash
   echo "BASE64_STRING" | base64 -d | nc 192.168.1.100 9100
   ```

3. **Verify with router**: The router will automatically use `print_data` if present

## Benefits of Server-Side Formatting

1. **Full control** over receipt design
2. **Complex features**: Images, QR codes, barcodes
3. **Easier updates**: Change formatting without touching router
4. **Better libraries**: Use proper ESC/POS libraries instead of shell scripting
5. **Consistent output**: Same formatting logic for all printers

## Files to Reference

- `/Users/pmcp/Projects/fyit-pos-printer/teltonika-print-server.sh` - Router script
- `/Users/pmcp/Projects/fyit-pos-printer/server-side-formatting.md` - Detailed examples
- `/Users/pmcp/Projects/fyit-pos-printer/docs/api_requirements.md` - API specs

## Key Points

- Router script already supports `print_data` field (base64 ESC/POS)
- Falls back to simple text if `print_data` not provided
- Each order must include `printer_ip` for multi-printer support
- API must return array of orders (even if just one)
- Orders are confirmed via POST to `/api/print-confirm` after printing









