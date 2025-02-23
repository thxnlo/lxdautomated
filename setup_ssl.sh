#!/bin/bash


setup_ssl() {
    local DOMAIN="$1"
    local WP_CONTAINER_NAME="${2:-wordpress-site}"  # Default if not provided
    local PROXY_CONTAINER_NAME="${3:-proxy}"        # Default if not provided
    local NGINX_CONFIG="/etc/nginx/sites-enabled/$DOMAIN"
    local NGINX_BACKUP="/etc/nginx/sites-available/$DOMAIN.bak"

    # Input validation
    if [ -z "$DOMAIN" ]; then
        echo "Error: Domain name is required"
        return 1
    fi

    # Verify container exists
    if ! lxc info "$PROXY_CONTAINER_NAME" >/dev/null 2>&1; then
        echo "Error: Container $PROXY_CONTAINER_NAME does not exist"
        return 1
    }

    echo "Starting SSL setup for domain: $DOMAIN"
    echo "Using proxy container: $PROXY_CONTAINER_NAME"

    # Install Certbot and dependencies
    echo "Installing Certbot and Nginx plugin..."
    if ! lxc exec "$PROXY_CONTAINER_NAME" -- bash -c "
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -y && 
        apt-get install -y certbot python3-certbot-nginx
    "; then
        echo "Error: Failed to install required packages"
        return 1
    fi

    # Setup SSL using Certbot
    echo "Obtaining SSL certificate for $DOMAIN..."
    if ! lxc exec "$PROXY_CONTAINER_NAME" -- certbot --nginx \
        -d "$DOMAIN" \
        --non-interactive \
        --agree-tos \
        --email "admin@$DOMAIN" \
        --redirect \
        --keep-until-expiring \
        --rsa-key-size 4096; then
        echo "Error: SSL certificate setup failed"
        return 1
    fi

    # Modify Nginx configuration
    echo "Configuring Nginx for SSL proxy_protocol..."
    if ! lxc exec "$PROXY_CONTAINER_NAME" -- bash -c "
        if [ ! -f '$NGINX_CONFIG' ]; then
            echo 'Error: Nginx configuration file not found'
            return 1
        fi

        # Create backup
        cp '$NGINX_CONFIG' '$NGINX_BACKUP'

        # Update SSL configuration with proxy_protocol
        sed -i '
            /listen 443 ssl;/c\    listen 443 ssl proxy_protocol;
            /listen \[::\]:443 ssl;/c\    listen [::]:443 ssl proxy_protocol;
            /listen \[::\]:443 ssl ipv6only=on;/c\    listen [::]:443 ssl proxy_protocol ipv6only=on;
        ' '$NGINX_CONFIG'

        # Add real IP configuration if not present
        if ! grep -q 'set_real_ip_from' '$NGINX_CONFIG'; then
            sed -i '/server {/a \    set_real_ip_from 10.0.0.0/8;\n    set_real_ip_from 172.16.0.0/12;\n    set_real_ip_from 192.168.0.0/16;\n    real_ip_header proxy_protocol;' '$NGINX_CONFIG'
        fi

        # Validate configuration
        if ! nginx -t; then
            echo 'Error: Invalid Nginx configuration'
            cp '$NGINX_BACKUP' '$NGINX_CONFIG'
            return 1
        fi
    "; then
        echo "Error: Failed to update Nginx configuration"
        return 1
    fi

    # Reload Nginx
    echo "Applying new configuration..."
    if ! lxc exec "$PROXY_CONTAINER_NAME" -- systemctl reload nginx; then
        echo "Error: Failed to reload Nginx"
        return 1
    fi

    # Setup auto-renewal with pre/post hooks
    echo "Configuring automatic renewal..."
    lxc exec "$PROXY_CONTAINER_NAME" -- bash -c "
        cat > /etc/cron.d/certbot-renew << 'EOF'
0 0,12 * * * root certbot renew --quiet --pre-hook 'systemctl stop nginx' --post-hook 'systemctl start nginx' --deploy-hook 'systemctl reload nginx'
EOF
        chmod 644 /etc/cron.d/certbot-renew
    "

    echo "✅ SSL setup completed successfully for $DOMAIN"
    echo "  - Certificate installed and configured"
    echo "  - Automatic renewal configured"
    echo "  - Proxy protocol enabled"
    return 0
}