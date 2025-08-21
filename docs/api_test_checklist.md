# API Implementation Test Checklist

## Pre-Implementation Verification

### Database Setup
- [ ] Orders table has `location_id` column
- [ ] Orders table has `status` column (default: 'pending')
- [ ] Orders table has `printed` boolean column (default: false)
- [ ] Orders table has `printed_at` timestamp column
- [ ] Index created on (location_id, status, printed)

### Environment Setup
- [ ] Generated secure API key (32+ characters)
- [ ] Added `PRINT_SERVER_API_KEY` to `.env`
- [ ] Verified Supabase/database credentials are set

## Endpoint Testing

### 1. GET /api/print-queue

#### Basic Functionality
- [ ] Returns 401 without API key
- [ ] Returns 401 with invalid API key
- [ ] Returns 400 without location_id parameter
- [ ] Returns empty array when no pending orders
- [ ] Returns orders for specific location only
- [ ] Orders are sorted by created_at (oldest first)
- [ ] Only returns orders with status='pending' and printed=false

#### Response Format
- [ ] Each order has `id` field
- [ ] Each order has `location_id` field
- [ ] Each order has `items` array
- [ ] Each item has `quantity`, `name`, `price`
- [ ] Each order has `total` field
- [ ] Each order has `customer` object (can be null)

#### Test Command
```bash
curl -H "X-API-Key: your-key" \
  "http://localhost:3000/api/print-queue?location_id=1"
```

### 2. GET /api/printers

#### Basic Functionality
- [ ] Returns 401 without API key
- [ ] Returns 401 with invalid API key
- [ ] Returns array of printer configurations
- [ ] Each printer has required fields

#### Response Format
- [ ] Each printer has `id` field
- [ ] Each printer has `name` field
- [ ] Each printer has `host` field (IP address)
- [ ] Each printer has `port` field (typically 9100)
- [ ] Each printer has `location_id` field
- [ ] Each printer has `type` field (receipt/kitchen/bar)

#### Test Command
```bash
curl -H "X-API-Key: your-key" \
  "http://localhost:3000/api/printers"
```

### 3. GET /api/settings

#### Basic Functionality
- [ ] Returns 401 without API key
- [ ] Returns 401 with invalid API key
- [ ] Returns settings object (not array)

#### Response Format
- [ ] Has `event_name` field
- [ ] Has `header` field
- [ ] Has `footer` field
- [ ] Has `currency` field
- [ ] Has `tax_rate` field (number)

#### Test Command
```bash
curl -H "X-API-Key: your-key" \
  "http://localhost:3000/api/settings"
```

### 4. PATCH /api/orders/[id]/status

#### Basic Functionality
- [ ] Returns 401 without API key
- [ ] Returns 401 with invalid API key
- [ ] Returns 404 for non-existent order ID
- [ ] Successfully updates order status
- [ ] Sets `printed=true` when status='printed'
- [ ] Updates `printed_at` timestamp
- [ ] Returns updated order in response

#### Request Format
- [ ] Accepts `status` field
- [ ] Accepts `printed_at` field
- [ ] Accepts `printer_used` field (optional)
- [ ] Accepts `error_message` field (optional)

#### Test Command
```bash
curl -X PATCH \
  -H "X-API-Key: your-key" \
  -H "Content-Type: application/json" \
  -d '{"status":"printed","printed_at":"2024-01-20T10:30:00Z"}' \
  "http://localhost:3000/api/orders/123/status"
```

## Integration Testing

### With Mock Print Server
- [ ] Start mock API server: `python tests/mock_api.py`
- [ ] Compare responses with mock implementation
- [ ] Verify data formats match

### With Real Print Server
- [ ] Configure print server with API URL and key
- [ ] Create test order in database
- [ ] Verify print server fetches order
- [ ] Verify status updates after printing
- [ ] Check order marked as printed in database

## Performance Testing

### Response Times
- [ ] Print queue responds in < 500ms
- [ ] Settings endpoint responds in < 200ms
- [ ] Status update completes in < 500ms

### Load Testing
- [ ] Print queue handles 10 requests/second
- [ ] No memory leaks with repeated polling
- [ ] Database connections properly closed

## Security Testing

### Authentication
- [ ] API key is required for all endpoints
- [ ] API key is case-sensitive
- [ ] Wrong API key returns 401, not 403
- [ ] No API endpoints exposed without auth

### Data Validation
- [ ] SQL injection attempts blocked
- [ ] Invalid order IDs handled gracefully
- [ ] Large request bodies rejected
- [ ] Rate limiting works (if implemented)

## Production Deployment

### Pre-Deployment
- [ ] All tests passing locally
- [ ] Environment variables set in Vercel
- [ ] Database migrations completed
- [ ] API key is different from development

### Post-Deployment
- [ ] Test each endpoint on production URL
- [ ] Verify HTTPS is enforced
- [ ] Check error logging is working
- [ ] Monitor first real order printing

## End-to-End Test Scenario

1. **Create Test Order**
   ```sql
   INSERT INTO orders (
     location_id, status, printed, total, 
     customer_name, notes
   ) VALUES (
     '1', 'pending', false, 25.50,
     'Test Customer', 'Test order for print server'
   );
   ```

2. **Verify Order Appears in Queue**
   ```bash
   curl -H "X-API-Key: your-key" \
     "https://your-app.vercel.app/api/print-queue?location_id=1"
   ```

3. **Simulate Print Server Update**
   ```bash
   curl -X PATCH \
     -H "X-API-Key: your-key" \
     -H "Content-Type: application/json" \
     -d '{"status":"printed","printed_at":"'$(date -u +"%Y-%m-%dT%H:%M:%SZ")'"}' \
     "https://your-app.vercel.app/api/orders/ORDER_ID/status"
   ```

4. **Verify Order No Longer in Queue**
   ```bash
   curl -H "X-API-Key: your-key" \
     "https://your-app.vercel.app/api/print-queue?location_id=1"
   ```

5. **Check Database**
   ```sql
   SELECT id, status, printed, printed_at 
   FROM orders 
   WHERE id = 'ORDER_ID';
   -- Should show: status='printed', printed=true, printed_at=timestamp
   ```

## Troubleshooting Guide

### Orders Not Appearing
1. Check location_id is set on orders
2. Verify status='pending' and printed=false
3. Check API key is correct
4. Verify database connection

### Authentication Failing
1. Check header name is exactly 'X-API-Key'
2. Verify no extra spaces in API key
3. Check environment variable is loaded
4. Try lowercase 'x-api-key' header

### Orders Printing Multiple Times
1. Verify status update endpoint works
2. Check printed flag is being set
3. Ensure database transaction commits
4. Check for print server timeout/retry

### Performance Issues
1. Add database indexes
2. Limit number of orders returned
3. Cache printer/settings endpoints
4. Use connection pooling

## Success Criteria

- [ ] All 4 endpoints implemented and tested
- [ ] Print server successfully polls and receives orders
- [ ] Orders print on thermal printer (or mock printer)
- [ ] Order status updates correctly after printing
- [ ] No errors in production logs
- [ ] Response times meet requirements
- [ ] Security checks pass

When all items are checked, the API implementation is complete and ready for production use with the print server.