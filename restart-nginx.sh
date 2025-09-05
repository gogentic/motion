#!/bin/bash
echo "Restarting nginx configuration for motion.gognetic.ai..."

# Test nginx config
sudo nginx -t

# Reload nginx
sudo systemctl reload nginx

# Test if it's working
sleep 2
if curl -s -H "Host: motion.gognetic.ai" http://localhost | grep -q "ComfyUI"; then
    echo "✅ motion.gognetic.ai is working!"
else
    echo "❌ Still showing default page. Checking site status..."
    ls -la /etc/nginx/sites-enabled/motion.gognetic.ai
    echo ""
    echo "Testing proxy directly:"
    curl -s -o /dev/null -w "%{http_code}\n" http://localhost:9188
fi