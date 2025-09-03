# Statements API Documentation

## Overview

The Statements API provides endpoints for managing and retrieving credit card or account statements. This mock implementation simulates a typical financial statements service.

## Base URL

```
http://localhost:8090
```

## Endpoints

### 1. Get Statement Information

Retrieve detailed information about a specific statement.

**Endpoint:** `GET /v1/statements/{statementId}`

**Path Parameters:**
- `statementId` (string, required) - The unique identifier of the statement

**Response:** `200 OK`

```json
{
  "id": "STMT-202411",
  "account_id": 123456789,
  "cycle": 1,
  "reference_date": "2024-11-30",
  "due_date": "2024-12-10",
  "closing_date": "2024-11-30",
  "opening_date": "2024-11-01",
  "status": "OPEN",
  "currency": "USD",
  "amounts": {
    "total": 2500.00,
    "minimum_payment": 250.00,
    "previous_balance": 1800.00,
    "credits": 500.00,
    "debits": 1200.00,
    "fees": 0.00,
    "interest": 0.00,
    "adjustments": 0.00
  },
  "summary": {
    "total_transactions": 42,
    "total_purchases": 35,
    "total_cash_advances": 2,
    "total_payments": 5,
    "total_fees": 0,
    "total_interest_charges": 0
  },
  "payment_info": {
    "minimum_payment_due": 250.00,
    "total_payment_due": 2500.00,
    "past_due_amount": 0.00,
    "over_limit_amount": 0.00
  },
  "credit_limit": 10000.00,
  "available_credit": 7500.00,
  "cash_advance_limit": 3000.00,
  "available_cash_advance": 3000.00,
  "created_at": "2024-12-01T00:00:00Z",
  "updated_at": "2024-12-01T00:00:00Z"
}
```

**Error Response:** `404 Not Found`

```json
{
  "error": {
    "code": "STATEMENT_NOT_FOUND",
    "message": "Statement with ID STMT-999 not found",
    "details": {
      "statement_id": "STMT-999",
      "timestamp": "2024-12-01T00:00:00Z"
    }
  }
}
```

### 2. List Account Statements

Get a list of all statements for a specific account.

**Endpoint:** `GET /v1/accounts/{accountId}/statements`

**Path Parameters:**
- `accountId` (string, required) - The account identifier

**Query Parameters:**
- `page` (integer, optional) - Page number for pagination (default: 1)
- `per_page` (integer, optional) - Items per page (default: 20)
- `status` (string, optional) - Filter by status (OPEN, CLOSED, PAID)

**Response:** `200 OK`

```json
{
  "statements": [
    {
      "id": "STMT-202411",
      "account_id": "123456789",
      "cycle": 1,
      "reference_date": "2024-11-30",
      "due_date": "2024-12-10",
      "status": "OPEN",
      "total_amount": 2500.00,
      "minimum_payment": 250.00,
      "currency": "USD"
    },
    {
      "id": "STMT-202410",
      "account_id": "123456789",
      "cycle": 2,
      "reference_date": "2024-10-31",
      "due_date": "2024-11-10",
      "status": "PAID",
      "total_amount": 1800.00,
      "minimum_payment": 180.00,
      "currency": "USD"
    }
  ],
  "pagination": {
    "page": 1,
    "per_page": 20,
    "total": 2,
    "total_pages": 1
  }
}
```

### 3. Get Statement Transactions

Retrieve all transactions associated with a specific statement.

**Endpoint:** `GET /v1/statements/{statementId}/transactions`

**Path Parameters:**
- `statementId` (string, required) - The statement identifier

**Query Parameters:**
- `type` (string, optional) - Filter by transaction type (PURCHASE, PAYMENT, FEE, INTEREST)
- `page` (integer, optional) - Page number
- `per_page` (integer, optional) - Items per page

**Response:** `200 OK`

```json
{
  "statement_id": "STMT-202411",
  "transactions": [
    {
      "id": "TXN-001",
      "transaction_date": "2024-11-28",
      "post_date": "2024-11-29",
      "description": "AMAZON.COM",
      "amount": 156.78,
      "type": "PURCHASE",
      "category": "RETAIL",
      "merchant": {
        "name": "Amazon",
        "category_code": "5999",
        "city": "Seattle",
        "country": "USA"
      },
      "authorization_code": "AUTH123456",
      "reference_number": "REF789012"
    },
    {
      "id": "TXN-002",
      "transaction_date": "2024-11-25",
      "post_date": "2024-11-26",
      "description": "STARBUCKS",
      "amount": 12.50,
      "type": "PURCHASE",
      "category": "FOOD",
      "merchant": {
        "name": "Starbucks",
        "category_code": "5814",
        "city": "New York",
        "country": "USA"
      }
    },
    {
      "id": "TXN-003",
      "transaction_date": "2024-11-20",
      "post_date": "2024-11-20",
      "description": "PAYMENT - THANK YOU",
      "amount": -500.00,
      "type": "PAYMENT",
      "category": "PAYMENT"
    }
  ],
  "summary": {
    "total_debits": 1200.00,
    "total_credits": 500.00,
    "transaction_count": 42
  }
}
```

### 4. Close Statement

Close an open statement and generate final balances.

**Endpoint:** `POST /v1/statements/{statementId}/close`

**Path Parameters:**
- `statementId` (string, required) - The statement to close

**Request Body:** None required

**Response:** `200 OK`

```json
{
  "id": "STMT-202411",
  "status": "CLOSED",
  "closed_at": "2024-12-01T00:00:00Z",
  "message": "Statement closed successfully"
}
```

### 5. Download Statement PDF

Get a download URL for the statement in PDF format.

**Endpoint:** `GET /v1/statements/{statementId}/pdf`

**Path Parameters:**
- `statementId` (string, required) - The statement identifier

**Response:** `200 OK`

```json
{
  "download_url": "https://statements.example.com/download/STMT-202411.pdf",
  "expires_at": "2024-12-01T01:00:00Z",
  "file_size_bytes": 245678,
  "generated_at": "2024-12-01T00:00:00Z"
}
```

## Data Types

### Statement Status
- `OPEN` - Statement is currently accumulating transactions
- `CLOSED` - Statement period has ended, awaiting payment
- `PAID` - Statement has been paid in full
- `OVERDUE` - Payment is past due date
- `PARTIAL_PAID` - Partial payment received

### Transaction Types
- `PURCHASE` - Regular purchase transaction
- `PAYMENT` - Payment received
- `CASH_ADVANCE` - Cash withdrawal
- `FEE` - Fee charged
- `INTEREST` - Interest charged
- `ADJUSTMENT` - Manual adjustment
- `REFUND` - Refund/credit

### Amount Fields
All monetary amounts are represented as decimal numbers with 2 decimal places.

### Date/Time Fields
- Dates are in `YYYY-MM-DD` format
- Timestamps are in ISO 8601 format: `YYYY-MM-DDTHH:mm:ssZ`

## Testing with Mock Server

### 1. Start the Mock Server

```bash
cd mock-api-server
go run cmd/main.go
```

### 2. Test Endpoints

```bash
# Get statement information
curl http://localhost:8090/v1/statements/STMT-202411

# List account statements  
curl http://localhost:8090/v1/accounts/123456789/statements

# Get statement transactions
curl http://localhost:8090/v1/statements/STMT-202411/transactions

# Close a statement
curl -X POST http://localhost:8090/v1/statements/STMT-202411/close

# Get PDF download URL
curl http://localhost:8090/v1/statements/STMT-202411/pdf

# Test error response
curl http://localhost:8090/v1/statements/INVALID-ID
```

### 3. Customize Responses

Edit `configs/statements-api.json` to modify:
- Response data values
- Add new test scenarios
- Simulate different error conditions
- Add response delays to simulate network latency

The mock server will hot-reload changes automatically.

## Integration Example

```javascript
// JavaScript/Node.js example
const axios = require('axios');

const STATEMENTS_API_URL = process.env.STATEMENTS_API_URL || 'http://localhost:8090';

async function getStatement(statementId) {
  try {
    const response = await axios.get(`${STATEMENTS_API_URL}/v1/statements/${statementId}`);
    return response.data;
  } catch (error) {
    if (error.response?.status === 404) {
      console.error('Statement not found');
    }
    throw error;
  }
}

async function listAccountStatements(accountId, page = 1) {
  const response = await axios.get(`${STATEMENTS_API_URL}/v1/accounts/${accountId}/statements`, {
    params: { page, per_page: 20 }
  });
  return response.data;
}

// Usage
(async () => {
  const statement = await getStatement('STMT-202411');
  console.log('Statement balance:', statement.amounts.total);
  
  const statements = await listAccountStatements('123456789');
  console.log('Total statements:', statements.pagination.total);
})();
```

## Notes

- All endpoints return JSON responses
- Use path parameters with `{paramName}` syntax - they'll be replaced in responses
- The mock server supports hot-reload - edit JSON files to see immediate changes
- Add `"delay": 1000` to any route to simulate network latency (in milliseconds)
- Create multiple JSON files for different test scenarios