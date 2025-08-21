# FriendlyPOS API Requirements

This document describes the API endpoints that need to be implemented in your FriendlyPOS web application for the print server to function correctly.

## Authentication

All API requests from the print server include an API key in the header:

```
X-API-Key: your-api-key-here
```

Your API should validate this key before processing requests.

## Required Endpoints

### 1. Get Print Queue

**Endpoint:** `GET /api/print-queue`

**Query Parameters:**
- `location_id` (required): The location identifier

**Headers:**
- `X-API-Key`: Authentication key

**Response:** Array of pending orders

```json
[
  {
    "id": "123",
    "location_id": "1",
    "status": "pending",
    "created_at": "2024-01-20T10:30:00Z",
    "items": [
      {
        "quantity": 2,
        "name": "Burger",
        "price": 12.50,
        "notes": "No onions"
      },
      {
        "quantity": 1,
        "name": "Fries",
        "price": 4.50
      }
    ],
    "total": 29.50,
    "customer": {
      "name": "John Doe",
      "phone": "555-1234",
      "email": "john@example.com"
    },
    "notes": "Table 5",
    "printer": "main"  // Optional: specific printer to use
  }
]
```

**Notes:**
- Return only orders that haven't been printed yet
- Filter by location_id
- Orders should be returned in creation order

### 2. Get Printer Configurations

**Endpoint:** `GET /api/printers`

**Headers:**
- `X-API-Key`: Authentication key

**Response:** Array of printer configurations

```json
[
  {
    "id": 1,
    "name": "main",
    "host": "192.168.1.100",
    "port": 9100,
    "location_id": "1",
    "type": "receipt",
    "enabled": true
  },
  {
    "id": 2,
    "name": "kitchen",
    "host": "192.168.1.101",
    "port": 9100,
    "location_id": "1",
    "type": "kitchen",
    "enabled": true
  }
]
```

**Notes:**
- Return all printers for all locations (print server will filter)
- Include disabled printers (print server will skip them)

### 3. Get Event Settings

**Endpoint:** `GET /api/settings`

**Headers:**
- `X-API-Key`: Authentication key

**Response:** Event-specific settings object

```json
{
  "event_name": "Summer Festival 2024",
  "header": "SUMMER FEST",
  "footer": "Thank you for your order!",
  "currency": "USD",
  "currency_symbol": "$",
  "tax_rate": 0.08,
  "print_customer_copy": false,
  "print_kitchen_copy": true,
  "logo_url": "https://example.com/logo.png",
  "receipt_width": 32,
  "custom_message": "Enjoy the festival!"
}
```

**Notes:**
- These settings customize receipt appearance
- All fields are optional
- Print server will use defaults for missing fields

### 4. Update Order Status

**Endpoint:** `PATCH /api/orders/:id/status`

**URL Parameters:**
- `id`: Order ID

**Headers:**
- `X-API-Key`: Authentication key
- `Content-Type`: application/json

**Request Body:**
```json
{
  "status": "printed",
  "printed_at": "2024-01-20T10:31:00Z",
  "printer_used": "main"
}
```

**Response:**
```json
{
  "success": true,
  "order": {
    "id": "123",
    "status": "printed",
    "printed_at": "2024-01-20T10:31:00Z"
  }
}
```

**Status Values:**
- `pending`: Order created, not yet printed
- `printed`: Successfully printed
- `failed`: Print failed (include error in request)
- `cancelled`: Order cancelled

## Error Handling

All endpoints should return appropriate HTTP status codes:

- `200 OK`: Success
- `401 Unauthorized`: Invalid or missing API key
- `404 Not Found`: Resource not found
- `500 Internal Server Error`: Server error

Error response format:
```json
{
  "error": "Invalid API key",
  "code": "AUTH_FAILED"
}
```

## Implementation Example (Node.js/Express)

```javascript
// Middleware for API key validation
const validateApiKey = (req, res, next) => {
  const apiKey = req.headers['x-api-key'];
  
  if (apiKey !== process.env.PRINT_SERVER_API_KEY) {
    return res.status(401).json({ 
      error: 'Invalid API key',
      code: 'AUTH_FAILED'
    });
  }
  
  next();
};

// Get print queue endpoint
app.get('/api/print-queue', validateApiKey, async (req, res) => {
  const { location_id } = req.query;
  
  const orders = await db.orders.findAll({
    where: {
      location_id,
      status: 'pending',
      printed: false
    },
    order: [['created_at', 'ASC']]
  });
  
  res.json(orders);
});

// Update order status
app.patch('/api/orders/:id/status', validateApiKey, async (req, res) => {
  const { id } = req.params;
  const { status, printed_at, printer_used } = req.body;
  
  const order = await db.orders.findByPk(id);
  
  if (!order) {
    return res.status(404).json({ 
      error: 'Order not found',
      code: 'NOT_FOUND'
    });
  }
  
  await order.update({
    status,
    printed: status === 'printed',
    printed_at,
    printer_used
  });
  
  res.json({
    success: true,
    order
  });
});
```

## Testing with Mock API

The print server includes a mock API server for testing:

```bash
# Start mock API server
python tests/mock_api.py --port 8080

# Configure print server to use mock API
# Edit config.env:
API_URL=http://localhost:8080
API_KEY=test-api-key

# Run print server
./run_dev.sh
```

## Security Considerations

1. **Use HTTPS in production** - All API communication should be encrypted
2. **Rotate API keys regularly** - Change keys periodically
3. **Implement rate limiting** - Prevent abuse of the print queue endpoint
4. **Validate printer IPs** - Only allow printing to known printer addresses
5. **Log all print requests** - Keep audit trail of what was printed

## Performance Considerations

1. **Pagination** - If you have many orders, implement pagination on the print queue endpoint
2. **Caching** - Cache printer configurations and settings (they don't change often)
3. **Database indexes** - Index on location_id and status for fast queries
4. **Connection pooling** - Use connection pooling for database queries

## Monitoring

Recommended metrics to track:

- Orders printed per hour/day
- Failed print attempts
- Average time from order creation to print
- Printer uptime/availability
- API response times

## WebSocket Support (Optional)

For real-time printing without polling, implement WebSocket support:

```javascript
// Server side
io.on('connection', (socket) => {
  socket.on('subscribe', ({ location_id }) => {
    socket.join(`location:${location_id}`);
  });
});

// When new order created
io.to(`location:${order.location_id}`).emit('new_order', order);
```

The print server currently uses polling but can be extended to support WebSockets for instant printing.