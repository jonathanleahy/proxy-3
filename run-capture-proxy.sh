#!/bin/bash
export CAPTURE_PORT=8091
export OUTPUT_DIR=./captured

# Set these to the REAL API URLs
export ACCOUNTS_API_URL="https://api-accounts.example.com"
export ACCOUNTS_CORE_API_URL="https://accounts-core-api.example.com"
export WALLET_API_URL="https://cards-api.example.com"
export LEDGER_API_API_URL="https://api-ledger.example.com"
export STATEMENTS_API_V2_URL="https://statements-api.example.com"
export AUTHORISATIONS_API_URL="https://api-authorizations.example.com"

cd mock-api-server
go run cmd/capture/main.go
