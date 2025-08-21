# Server-Side Print Formatting Best Practices

## Recommended Approach: Pre-formatted ESC/POS Commands

The best way to handle receipt formatting is to generate the complete ESC/POS command sequence on your server and send it to the Teltonika router. This gives you full control over the design without space limitations.

## Implementation Options

### Option 1: Base64 Encoded ESC/POS (Recommended)

**Server sends:**
```json
{
  "id": "123",
  "printer_ip": "192.168.1.100",
  "print_data": "G1tAG1thAR0hMEZSSUVORExZIFBPUx0hAA0KG1thAA0K..."
}
```

**Benefits:**
- Complete control over formatting
- Binary-safe transmission
- No parsing needed on router
- Can include images, barcodes, QR codes

**Server-side example (Node.js):**
```javascript
const escpos = require('escpos');
// or build commands manually:

function generateReceipt(order) {
  const commands = [];
  
  // Initialize
  commands.push(Buffer.from([0x1B, 0x40]));
  
  // Center + Double size header
  commands.push(Buffer.from([0x1B, 0x61, 0x01])); // center
  commands.push(Buffer.from([0x1D, 0x21, 0x30])); // double
  commands.push(Buffer.from('FRIENDLY POS\n'));
  
  // Add items, total, etc.
  // ...
  
  // Cut
  commands.push(Buffer.from([0x1D, 0x56, 0x00]));
  
  // Combine and encode
  const receipt = Buffer.concat(commands);
  return receipt.toString('base64');
}

// In your API response:
res.json({
  id: order.id,
  printer_ip: order.printer_ip,
  print_data: generateReceipt(order)
});
```

### Option 2: Structured Data with Template

**Server sends:**
```json
{
  "id": "123",
  "printer_ip": "192.168.1.100",
  "receipt": {
    "header": "FRIENDLY POS",
    "subheader": "Order Receipt",
    "order_num": "123",
    "items": [
      {"name": "Burger", "qty": 2, "price": 12.50},
      {"name": "Fries", "qty": 1, "price": 4.50}
    ],
    "total": 29.50,
    "footer": "Thank You!",
    "barcode": "123456"
  }
}
```

**Benefits:**
- Human-readable API
- Easy to debug
- Can still control layout

**Drawback:**
- Router needs more complex parsing
- Limited by shell script capabilities

### Option 3: Raw ESC/POS in Hex String

**Server sends:**
```json
{
  "id": "123",
  "printer_ip": "192.168.1.100",
  "print_hex": "1b401b6101..."
}
```

Convert on router:
```bash
echo "$PRINT_HEX" | xxd -r -p | nc $PRINTER_IP 9100
```

## Recommended Libraries

### Node.js/JavaScript:
- `escpos`: Full-featured ESC/POS library
- `node-thermal-printer`: Simple thermal printer library
- `receiptline`: Markdown-like syntax for receipts

### Python:
- `python-escpos`: Comprehensive ESC/POS support
- `pySerial`: For direct printer communication

### Example with node-thermal-printer:
```javascript
const ThermalPrinter = require('node-thermal-printer').printer;
const Types = require('node-thermal-printer').types;

const printer = new ThermalPrinter({
  type: Types.EPSON,
  interface: 'tcp://192.168.1.100'
});

printer.alignCenter();
printer.setTextDoubleHeight();
printer.println('FRIENDLY POS');
printer.setTextNormal();
printer.drawLine();

// Add items
order.items.forEach(item => {
  printer.leftRight(
    `${item.qty}x ${item.name}`,
    `$${item.price * item.qty}`
  );
});

printer.drawLine();
printer.setTextDoubleWidth();
printer.leftRight('TOTAL:', `$${order.total}`);

printer.cut();

// Get buffer and encode
const commands = printer.getBuffer();
const base64 = Buffer.from(commands).toString('base64');
```

## Testing Your Format

1. Generate ESC/POS on server
2. Save to file: `echo "BASE64_STRING" | base64 -d > test.prn`
3. Test print: `cat test.prn | nc 192.168.1.100 9100`

## Current Router Implementation

The updated Teltonika script now:
1. Checks for `print_data` field in the order
2. If found, decodes base64 and sends directly to printer
3. Falls back to simple text format if not provided

This gives you flexibility to gradually migrate to server-side formatting while maintaining backwards compatibility.