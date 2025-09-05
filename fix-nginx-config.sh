#!/bin/bash

echo "Checking nginx configuration..."

# Test if motion.gognetic.ai config is correct
if curl -s -H "Host: motion.gognetic.ai" http://localhost | grep -q "ComfyUI"; then
    echo "✓ Nginx is correctly proxying to ComfyUI"
else
    echo "✗ Nginx not proxying correctly. Reloading..."
    sudo nginx -t && sudo systemctl reload nginx
    sleep 2
    
    # Test again
    if curl -s -H "Host: motion.gognetic.ai" http://localhost | grep -q "ComfyUI"; then
        echo "✓ Fixed! Nginx is now proxying correctly"
    else
        echo "✗ Still not working. Checking config..."
        ls -la /etc/nginx/sites-enabled/motion*
        echo ""
        echo "Testing proxy_pass directly:"
        curl -I http://localhost:9188
    fi
fi

echo ""
echo "You should now be able to access: http://motion.gognetic.ai"