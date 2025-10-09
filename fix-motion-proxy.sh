#!/bin/bash

echo "Fixing motion.gogentic.ai to proxy to ComfyUI..."

# Create proper config for motion.gogentic.ai
cat > /tmp/motion.gogentic.ai.conf << 'EOF'
server {
    listen 80;
    listen [::]:80;
    server_name motion.gogentic.ai;
    return 301 https://$server_name$request_uri;
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name motion.gogentic.ai;

    # SSL certificates from certbot
    ssl_certificate /etc/letsencrypt/live/motion.gogentic.ai/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/motion.gogentic.ai/privkey.pem;
    include /etc/letsencrypt/options-ssl-nginx.conf;
    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;

    # Proxy to ComfyUI
    location / {
        proxy_pass http://127.0.0.1:9188;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        # WebSocket support
        proxy_buffering off;
        proxy_cache off;
        proxy_connect_timeout 36000;
        proxy_send_timeout 36000;
        proxy_read_timeout 36000;
        
        # Increase body size for uploads
        client_max_body_size 100M;
    }
    
    location /ws {
        proxy_pass http://127.0.0.1:9188/ws;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_buffering off;
        proxy_cache off;
    }
}
EOF

# Backup current config
sudo cp /etc/nginx/sites-enabled/default /etc/nginx/sites-enabled/default.backup

# Remove motion.gogentic.ai from default site and create dedicated config
sudo cp /tmp/motion.gogentic.ai.conf /etc/nginx/sites-available/motion.gogentic.ai

# Remove old incorrect spelling if it exists
sudo rm -f /etc/nginx/sites-enabled/motion.gognetic.ai
sudo rm -f /etc/nginx/sites-enabled/motion.gogentic.ai

# Create new symlink
sudo ln -s /etc/nginx/sites-available/motion.gogentic.ai /etc/nginx/sites-enabled/

# Test nginx configuration
sudo nginx -t

if [ $? -eq 0 ]; then
    sudo systemctl reload nginx
    echo "✅ Configuration fixed! Testing..."
    sleep 2
    
    if curl -s https://motion.gogentic.ai 2>/dev/null | grep -q "ComfyUI"; then
        echo "✅ Success! https://motion.gogentic.ai is now proxying to ComfyUI"
    else
        echo "⚠️ Site is accessible but check if it's showing ComfyUI interface"
    fi
else
    echo "❌ Nginx configuration error. Please check manually."
fi
