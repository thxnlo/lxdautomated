#!/bin/bash


#file: setup_ssl.sh

setup_ssl() {
    local DOMAIN="$1"
    local WP_CONTAINER_NAME="${2:-wordpress-site}"  # Default if not provided
    local PROXY_CONTAINER_NAME="${3:-proxy}"        # Default if not provided

    # Validate inputs
    if [ -z "$DOMAIN" ]; then
        echo "Error: Domain name is required"
        return 1
    fi

    echo "Debug: Setting up SSL with:"
    echo "DOMAIN=$DOMAIN"
    echo "PROXY_CONTAINER_NAME=$PROXY_CONTAINER_NAME"

    # Install Certbot and dependencies
    echo "Installing Certbot and Nginx plugin for SSL..."
    if ! lxc exec "$PROXY_CONTAINER_NAME" -- apt update -y; then
        echo "Error: Failed to update package list"
        return 1
    fi

    if ! lxc exec "$PROXY_CONTAINER_NAME" -- apt install -y certbot python3-certbot-nginx; then
        echo "Error: Failed to install Certbot"
        return 1
    fi

    # Setup SSL using Certbot
    echo "Setting up SSL certificate for $DOMAIN..."
    if ! lxc exec "$PROXY_CONTAINER_NAME" -- certbot --nginx \
        -d "$DOMAIN" \
        --non-interactive \
        --agree-tos \
        --email "admin@$DOMAIN" \
        --redirect; then
        echo "Error: SSL certificate setup failed"
        return 1
    fi

    # Modify Nginx configuration for SSL proxy_protocol
    echo "Modifying Nginx configuration for SSL proxy_protocol..."
    lxc exec "$PROXY_CONTAINER_NAME" -- bash -c "
        if [ -f /etc/nginx/sites-enabled/$DOMAIN ]; then
            # Backup original configuration
            cp /etc/nginx/sites-enabled/$DOMAIN /etc/nginx/sites-enabled/$DOMAIN.bak
            
            # Add proxy_protocol to SSL listen directives
            sed -i '/listen 443 ssl;/c\    listen 443 ssl proxy_protocol;' /etc/nginx/sites-enabled/$DOMAIN
            sed -i '/listen \[::\]:443 ssl;/c\    listen [::]:443 ssl proxy_protocol;' /etc/nginx/sites-enabled/$DOMAIN
            
            # Test Nginx configuration
            if ! nginx -t; then
                echo 'Error: Invalid Nginx configuration'
                cp /etc/nginx/sites-enabled/$DOMAIN.bak /etc/nginx/sites-available/$DOMAIN
                return 1
            fi
        else
            echo 'Error: Nginx configuration file not found'
            return 1
        fi
    "

    # Reload Nginx
    echo "Reloading Nginx to apply SSL and proxy_protocol changes..."
    if ! lxc exec "$PROXY_CONTAINER_NAME" -- systemctl reload nginx; then
        echo "Error: Failed to reload Nginx"
        return 1
    fi

    # Setup auto-renewal
    echo "Setting up SSL certificate renewal cron job..."
    lxc exec "$PROXY_CONTAINER_NAME" -- bash -c "
        echo '0 0,12 * * * root certbot renew --quiet && systemctl reload nginx' > /etc/cron.d/certbot-renew
        chmod 644 /etc/cron.d/certbot-renew
    "

    echo "✅ SSL certificate successfully set up for $DOMAIN!"
    return 0
}