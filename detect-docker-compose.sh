#!/bin/bash
# Detect and use the right docker compose command

if command -v docker-compose &> /dev/null; then
    echo "docker-compose"
elif docker compose version &> /dev/null 2>&1; then
    echo "docker compose"  
else
    echo "ERROR: Neither 'docker-compose' nor 'docker compose' found!" >&2
    exit 1
fi