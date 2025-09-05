#!/bin/bash

echo "Testing ComfyUI Access Methods"
echo "==============================="
echo ""

echo "1. Direct local access (should work):"
curl -s -o /dev/null -w "%{http_code}" http://localhost:9188
echo ""

echo "2. Via 127.0.0.1 (should work):"
curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:9188
echo ""

echo "3. Container is running:"
docker ps | grep -E "comfyui|motion" | awk '{print $1, $2, $NF}'
echo ""

echo "4. Port is listening:"
ss -tln | grep 9188
echo ""

echo "5. Test page content:"
curl -s http://localhost:9188 2>/dev/null | grep -o "<title>.*</title>" || echo "No title found"
echo ""

echo "For SSH tunnel from your LOCAL machine, use:"
echo "ssh -L 9188:localhost:9188 ira@$(curl -s ifconfig.me 2>/dev/null || echo "YOUR_SERVER_IP")"
echo ""
echo "Then access: http://localhost:9188"