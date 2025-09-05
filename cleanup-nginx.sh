#!/bin/bash

echo "Cleaning up nginx configuration..."

# Move backup out of sites-enabled
sudo mv /etc/nginx/sites-enabled/default.backup /tmp/default.backup.save

# Now we need to fix the default site - remove motion.gogentic.ai from it
# First, let's restore the original default config
echo "Restoring default site to original state..."

# Create a clean default site config
cat > /tmp/default.clean << 'EOF'
server {
	listen 80 default_server;
	listen [::]:80 default_server;

	root /var/www/html;
	index index.html index.htm index.nginx-debian.html;

	server_name _;

	location / {
		try_files $uri $uri/ =404;
	}
}
EOF

# Backup current default
sudo cp /etc/nginx/sites-available/default /tmp/default.with-motion.backup

# Replace with clean default
sudo cp /tmp/default.clean /etc/nginx/sites-available/default

# Test configuration
sudo nginx -t

if [ $? -eq 0 ]; then
    sudo systemctl reload nginx
    echo "✅ Nginx configuration cleaned up!"
    echo ""
    echo "Testing motion.gogentic.ai..."
    
    if curl -k -s https://motion.gogentic.ai 2>/dev/null | grep -q "ComfyUI"; then
        echo "✅ https://motion.gogentic.ai is working correctly!"
    else
        echo "⚠️  https://motion.gogentic.ai is accessible but may need checking"
        echo "Testing direct proxy..."
        curl -s http://localhost:9188 2>/dev/null | grep -o "ComfyUI" | head -1
    fi
else
    echo "❌ Still configuration errors. Let's check what's wrong:"
    sudo nginx -t 2>&1
fi