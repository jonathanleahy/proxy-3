#!/bin/bash
# Simple viewer for captured requests

echo "📊 Captured HTTPS Requests"
echo "=========================="
echo ""

# Show latest captures
for file in $(ls -t captured/*.json | head -5); do
    echo "📁 $(basename $file)"
    cat "$file" | jq -r '.requests[]? | "  \(.method) \(.url) - \(.timestamp)"' 2>/dev/null || \
    cat "$file" | jq -r 'if .url then "  \(.method // "GET") \(.url)" else empty end' 2>/dev/null || \
    echo "  (Raw capture data)"
    echo ""
done

echo "Total captures: $(ls -1 captured/*.json 2>/dev/null | wc -l)"
echo ""
echo "View specific file: cat captured/<filename> | jq '.'"