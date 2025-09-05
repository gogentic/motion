#!/bin/bash
echo "Fixing NGINX configuration..."

# Remove default site
sudo rm -f /etc/nginx/sites-enabled/default

# Test configuration
sudo nginx -t

# Reload nginx
sudo systemctl reload nginx

echo "Done! Default site removed."
echo "Test locally with: curl -H 'Host: motion.gognetic.ai' http://localhost"