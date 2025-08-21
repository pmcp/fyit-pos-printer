# FriendlyPOS Print Server API Implementation Brief

## For: Claude Code Implementation in Nuxt Application

### Executive Summary
You need to implement 4 API endpoints in the FriendlyPOS Nuxt application to enable communication with a local print server running on Teltonika routers at event venues. The print server polls these endpoints to fetch orders and print them on thermal printers.

## Architecture Overview

```
┌─────────────────┐         ┌──────────────────┐         ┌─────────────────┐
│   Customer      │────────▶│  FriendlyPOS     │         │  Print Server   │
│   (Browser)     │         │  (Vercel/Nuxt)   │◀────────│  (Router)       │
└─────────────────┘         └──────────────────┘  Polls  └─────────────────┘
                                     │                            │
                                     ▼                            ▼
                            ┌──────────────────┐         ┌─────────────────┐
                            │   Supabase/Neon  │         │ Thermal Printer │
                            │   (Database)     │         │ (Local Network) │
                            └──────────────────┘         └─────────────────┘
```

### How It Works
1. Customers place orders through the web app
2. Orders are saved to the database with a `location_id`
3. Print server at each location polls the API every 2 seconds
4. API returns pending orders for that specific location
5. Print server sends orders to local thermal printers
6. Print server updates order status via API

## Implementation Requirements

### Prerequisites
- Nuxt 3 application
- Supabase/Neon PostgreSQL database
- Environment variable: `PRINT_SERVER_API_KEY`

### Database Schema Requirements

Add these fields to your `orders` table if not present:

```sql
-- Required fields
ALTER TABLE orders ADD COLUMN IF NOT EXISTS location_id VARCHAR(255);
ALTER TABLE orders ADD COLUMN IF NOT EXISTS status VARCHAR(50) DEFAULT 'pending';
ALTER TABLE orders ADD COLUMN IF NOT EXISTS printed BOOLEAN DEFAULT false;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS printed_at TIMESTAMP;

-- Create index for performance
CREATE INDEX IF NOT EXISTS idx_orders_print_queue 
ON orders(location_id, status, printed) 
WHERE status = 'pending' AND printed = false;
```

## API Endpoints to Implement

### 1. GET /api/print-queue

**Purpose**: Returns unprinted orders for a specific location

**File Location**: `/server/api/print-queue.get.ts` (Nuxt 3)

```typescript
// /server/api/print-queue.get.ts
import { createClient } from '@supabase/supabase-js'

export default defineEventHandler(async (event) => {
  // 1. Validate API key
  const apiKey = getHeader(event, 'x-api-key')
  if (apiKey !== process.env.PRINT_SERVER_API_KEY) {
    throw createError({
      statusCode: 401,
      statusMessage: 'Invalid API key'
    })
  }

  // 2. Get location_id from query params
  const query = getQuery(event)
  const location_id = query.location_id as string
  
  if (!location_id) {
    throw createError({
      statusCode: 400,
      statusMessage: 'location_id is required'
    })
  }

  // 3. Initialize Supabase client
  const supabase = createClient(
    process.env.SUPABASE_URL!,
    process.env.SUPABASE_SERVICE_KEY!
  )

  // 4. Fetch pending orders
  const { data: orders, error } = await supabase
    .from('orders')
    .select(`
      id,
      location_id,
      status,
      created_at,
      total,
      notes,
      customer_name,
      customer_phone,
      customer_email,
      order_items (
        id,
        quantity,
        name,
        price,
        notes
      )
    `)
    .eq('location_id', location_id)
    .eq('status', 'pending')
    .eq('printed', false)
    .order('created_at', { ascending: true })
    .limit(10) // Prevent overwhelming the printer

  if (error) {
    throw createError({
      statusCode: 500,
      statusMessage: 'Database error'
    })
  }

  // 5. Format response for print server
  return (orders || []).map(order => ({
    id: order.id,
    location_id: order.location_id,
    status: order.status,
    created_at: order.created_at,
    items: order.order_items.map(item => ({
      quantity: item.quantity,
      name: item.name,
      price: item.price,
      notes: item.notes
    })),
    total: order.total,
    customer: {
      name: order.customer_name,
      phone: order.customer_phone,
      email: order.customer_email
    },
    notes: order.notes
  }))
})
```

### 2. GET /api/printers

**Purpose**: Returns printer configurations for all locations

**File Location**: `/server/api/printers.get.ts`

```typescript
// /server/api/printers.get.ts
export default defineEventHandler(async (event) => {
  // 1. Validate API key
  const apiKey = getHeader(event, 'x-api-key')
  if (apiKey !== process.env.PRINT_SERVER_API_KEY) {
    throw createError({
      statusCode: 401,
      statusMessage: 'Invalid API key'
    })
  }

  // 2. Return printer configurations
  // These can be hardcoded or fetched from a database table
  return [
    {
      id: 1,
      name: 'main',
      host: '192.168.1.100',  // Local IP at venue
      port: 9100,
      location_id: '1',
      type: 'receipt',
      enabled: true
    },
    {
      id: 2,
      name: 'kitchen',
      host: '192.168.1.101',
      port: 9100,
      location_id: '1',
      type: 'kitchen',
      enabled: true
    },
    {
      id: 3,
      name: 'bar',
      host: '192.168.1.102',
      port: 9100,
      location_id: '1',
      type: 'bar',
      enabled: true
    }
  ]
  
  // Alternative: Fetch from database
  /*
  const supabase = createClient(
    process.env.SUPABASE_URL!,
    process.env.SUPABASE_SERVICE_KEY!
  )
  
  const { data: printers } = await supabase
    .from('printers')
    .select('*')
    .eq('enabled', true)
  
  return printers
  */
})
```

### 3. GET /api/settings

**Purpose**: Returns event-specific receipt settings

**File Location**: `/server/api/settings.get.ts`

```typescript
// /server/api/settings.get.ts
export default defineEventHandler(async (event) => {
  // 1. Validate API key
  const apiKey = getHeader(event, 'x-api-key')
  if (apiKey !== process.env.PRINT_SERVER_API_KEY) {
    throw createError({
      statusCode: 401,
      statusMessage: 'Invalid API key'
    })
  }

  // 2. Return settings (can be from database or environment)
  return {
    event_name: process.env.EVENT_NAME || 'FriendlyPOS',
    header: process.env.RECEIPT_HEADER || 'WELCOME',
    footer: process.env.RECEIPT_FOOTER || 'Thank you for your order!',
    currency: 'EUR',
    currency_symbol: '€',
    tax_rate: 0.21,
    print_customer_copy: false,
    print_kitchen_copy: true,
    receipt_width: 32,
    show_queue_number: true,
    queue_number_prefix: 'ORDER #'
  }
  
  // Alternative: Fetch from database
  /*
  const supabase = createClient(
    process.env.SUPABASE_URL!,
    process.env.SUPABASE_SERVICE_KEY!
  )
  
  const { data: settings } = await supabase
    .from('event_settings')
    .select('*')
    .single()
  
  return settings
  */
})
```

### 4. PATCH /api/orders/[id]/status

**Purpose**: Updates order status after printing

**File Location**: `/server/api/orders/[id]/status.patch.ts`

```typescript
// /server/api/orders/[id]/status.patch.ts
import { createClient } from '@supabase/supabase-js'

export default defineEventHandler(async (event) => {
  // 1. Validate API key
  const apiKey = getHeader(event, 'x-api-key')
  if (apiKey !== process.env.PRINT_SERVER_API_KEY) {
    throw createError({
      statusCode: 401,
      statusMessage: 'Invalid API key'
    })
  }

  // 2. Get order ID from URL
  const id = getRouterParam(event, 'id')
  if (!id) {
    throw createError({
      statusCode: 400,
      statusMessage: 'Order ID is required'
    })
  }

  // 3. Get update data from request body
  const body = await readBody(event)
  const { status, printed_at, printer_used, error_message } = body

  // 4. Initialize Supabase client
  const supabase = createClient(
    process.env.SUPABASE_URL!,
    process.env.SUPABASE_SERVICE_KEY!
  )

  // 5. Update order in database
  const updateData: any = {
    status,
    printed: status === 'printed',
    updated_at: new Date().toISOString()
  }

  if (printed_at) updateData.printed_at = printed_at
  if (printer_used) updateData.printer_used = printer_used
  if (error_message) updateData.print_error = error_message

  const { data: order, error } = await supabase
    .from('orders')
    .update(updateData)
    .eq('id', id)
    .select()
    .single()

  if (error) {
    throw createError({
      statusCode: 500,
      statusMessage: 'Failed to update order'
    })
  }

  if (!order) {
    throw createError({
      statusCode: 404,
      statusMessage: 'Order not found'
    })
  }

  // 6. Log print event (optional)
  await supabase
    .from('print_logs')
    .insert({
      order_id: id,
      status,
      printer_used,
      printed_at,
      error_message
    })

  return {
    success: true,
    order
  }
})
```

## Environment Variables Required

Add to your `.env` file in the Nuxt project:

```bash
# Print Server Authentication
PRINT_SERVER_API_KEY=generate-a-secure-32-char-key-here

# Optional: Receipt customization
EVENT_NAME="FriendlyPOS Event"
RECEIPT_HEADER="WELCOME TO OUR EVENT"
RECEIPT_FOOTER="Thank you for your order!"

# If using Supabase
SUPABASE_URL=your-supabase-url
SUPABASE_SERVICE_KEY=your-service-key
```

Generate a secure API key:
```bash
openssl rand -hex 32
```

## Testing the Implementation

### 1. Test Individual Endpoints

```bash
# Set your API key and URL
API_KEY="your-generated-key"
API_URL="http://localhost:3000"  # or your Vercel URL

# Test print queue
curl -H "X-API-Key: $API_KEY" \
  "$API_URL/api/print-queue?location_id=1"

# Test printers
curl -H "X-API-Key: $API_KEY" \
  "$API_URL/api/printers"

# Test settings
curl -H "X-API-Key: $API_KEY" \
  "$API_URL/api/settings"

# Test status update
curl -X PATCH \
  -H "X-API-Key: $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"status":"printed","printed_at":"2024-01-20T10:30:00Z"}' \
  "$API_URL/api/orders/123/status"
```

### 2. Test with Mock Print Server

```bash
# In the print server directory
cd friendlypos-print-server

# Update config.env with your API URL
echo "API_URL=$API_URL" >> config.env
echo "API_KEY=$API_KEY" >> config.env
echo "LOCATION_ID=1" >> config.env

# Run integration test
python tests/integration_test.py
```

## Security Considerations

1. **API Key Storage**: Never commit the API key to git. Use environment variables.

2. **HTTPS Only**: In production, ensure all communication uses HTTPS:
   ```typescript
   if (process.env.NODE_ENV === 'production' && !event.node.req.secure) {
     throw createError({ statusCode: 403, statusMessage: 'HTTPS required' })
   }
   ```

3. **Rate Limiting**: Consider adding rate limiting to prevent abuse:
   ```typescript
   // Use a rate limiting package or implement manually
   const ip = getClientIP(event)
   if (rateLimiter.isExceeded(ip)) {
     throw createError({ statusCode: 429, statusMessage: 'Too many requests' })
   }
   ```

4. **IP Whitelisting** (optional): If router IPs are static:
   ```typescript
   const allowedIPs = process.env.ALLOWED_IPS?.split(',') || []
   const clientIP = getClientIP(event)
   if (!allowedIPs.includes(clientIP)) {
     throw createError({ statusCode: 403, statusMessage: 'IP not allowed' })
   }
   ```

## Common Issues and Solutions

### Issue: Orders not appearing in print queue
- Check `location_id` is set correctly on orders
- Verify `status = 'pending'` and `printed = false`
- Check database indexes for performance

### Issue: Authentication failing
- Ensure `X-API-Key` header is sent (capital K in Key)
- Verify API key matches in both systems
- Check for trailing spaces in environment variables

### Issue: Orders printing multiple times
- Ensure status update endpoint is working
- Check that `printed` flag is being set to `true`
- Verify print server is receiving success response

## Implementation Checklist

- [ ] Create `/server/api/` directory if not exists
- [ ] Implement `print-queue.get.ts`
- [ ] Implement `printers.get.ts`
- [ ] Implement `settings.get.ts`
- [ ] Implement `orders/[id]/status.patch.ts`
- [ ] Add `PRINT_SERVER_API_KEY` to `.env`
- [ ] Update database schema if needed
- [ ] Test each endpoint with curl
- [ ] Run integration test with print server
- [ ] Deploy to Vercel
- [ ] Test with production print server

## Next Steps After Implementation

1. **Deploy to Vercel**: Push changes and verify endpoints are accessible
2. **Configure Print Server**: Update print server's `config.env` with:
   - Your Vercel app URL
   - The API key you generated
   - The correct location_id
3. **Test End-to-End**: Create an order in the web app and verify it prints

## Support Information

- Print Server Documentation: `/docs/api_requirements.md`
- Print Server Repository: `friendlypos-print-server`
- Test Tools: `/tests/mock_api.py` (reference implementation)

This implementation will enable the print server to fetch and print orders from your FriendlyPOS application.