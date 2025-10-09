#!/bin/bash

echo "NGINX Setup for MOTION"
echo "====================="
echo ""

# Check if running with sudo
if [ "$EUID" -ne 0 ]; then 
   echo "Please run with sudo: sudo ./setup_nginx.sh"
   exit 1
fi

# Choose subdomain
echo "Choose your setup:"
echo "1. motion.gognetic.ai (WebUI only)"
echo "2. motion-api.gognetic.ai (API only)"
echo "3. Both subdomains"
read -p "Enter choice (1-3): " choice

case $choice in
    1)
        DOMAINS="motion.gognetic.ai"
        SETUP_WEB=true
        SETUP_API=false
        ;;
    2)
        DOMAINS="motion-api.gognetic.ai"
        SETUP_WEB=false
        SETUP_API=true
        ;;
    3)
        DOMAINS="motion.gognetic.ai motion-api.gognetic.ai"
        SETUP_WEB=true
        SETUP_API=true
        ;;
    *)
        echo "Invalid choice"
        exit 1
        ;;
esac

# Install NGINX if needed
if ! command -v nginx &> /dev/null; then
    echo "Installing NGINX..."
    apt-get update
    apt-get install -y nginx certbot python3-certbot-nginx
fi

# Setup NGINX configs
if [ "$SETUP_WEB" = true ]; then
    echo "Setting up motion.gognetic.ai..."
    
    cat > /etc/nginx/sites-available/motion.gognetic.ai << 'EOF'
server {
    listen 80;
    server_name motion.gognetic.ai;
    
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
    
    ln -sf /etc/nginx/sites-available/motion.gognetic.ai /etc/nginx/sites-enabled/
fi

if [ "$SETUP_API" = true ]; then
    echo "Setting up motion-api.gognetic.ai..."
    
    cat > /etc/nginx/sites-available/motion-api.gognetic.ai << 'EOF'
server {
    listen 80;
    server_name motion-api.gognetic.ai;
    
    location / {
        proxy_pass http://127.0.0.1:9000;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        proxy_connect_timeout 36000;
        proxy_send_timeout 36000;
        proxy_read_timeout 36000;
        
        client_max_body_size 100M;
    }
}
EOF
    
    ln -sf /etc/nginx/sites-available/motion-api.gognetic.ai /etc/nginx/sites-enabled/
fi

# Test NGINX config
echo "Testing NGINX configuration..."
nginx -t

if [ $? -eq 0 ]; then
    echo "✓ NGINX configuration valid"
    
    # Reload NGINX
    systemctl reload nginx
    echo "✓ NGINX reloaded"
    
    # Setup SSL with Let's Encrypt
    echo ""
    echo "Would you like to setup SSL with Let's Encrypt? (y/n)"
    read -p "Choice: " ssl_choice
    
    if [[ "$ssl_choice" =~ ^[Yy]$ ]]; then
        for domain in $DOMAINS; do
            certbot --nginx -d $domain
        done
    fi
    
    echo ""
    echo "✅ Setup complete!"
    echo ""
    echo "Access your services at:"
    if [ "$SETUP_WEB" = true ]; then
        echo "  WebUI: https://motion.gognetic.ai"
    fi
    if [ "$SETUP_API" = true ]; then
        echo "  API:   https://motion-api.gognetic.ai"
    fi
    
    # Optional: Setup basic auth
    echo ""
    echo "Would you like to add password protection? (y/n)"
    read -p "Choice: " auth_choice
    
    if [[ "$auth_choice" =~ ^[Yy]$ ]]; then
        echo "Enter username:"
        read username
        htpasswd -c /etc/nginx/.htpasswd.motion $username
        
        # Add auth to configs
        for site in motion.gognetic.ai motion-api.gognetic.ai; do
            if [ -f /etc/nginx/sites-available/$site ]; then
                sed -i '/location \/ {/a \    auth_basic "MOTION Access";\n    auth_basic_user_file /etc/nginx/.htpasswd.motion;' /etc/nginx/sites-available/$site
            fi
        done
        
        systemctl reload nginx
        echo "✓ Password protection added"
    fi
else
    echo "✗ NGINX configuration error. Please check the config."
    exit 1
fi

echo ""
echo "Next steps:"
echo "1. Update DNS to point subdomain(s) to this server"
echo "2. Ensure ports 80 and 443 are open in firewall"
echo "3. Start the appropriate service:"
echo "   - For WebUI: ./launch_webui.sh"
echo "   - For API:   ./start.sh"
