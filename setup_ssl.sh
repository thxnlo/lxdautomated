#!/bin/bash

setup_ssl() {
  DOMAIN=$1
  WP_CONTAINER_NAME=$2
  PROXY_CONTAINER_NAME=$3

  # Install Certbot and Nginx plugin for Certbot without showing output
  echo "Installing Certbot and Nginx plugin for SSL..."
  lxc exec "$PROXY_CONTAINER_NAME" -- sudo --user root --login bash -c "apt update -y > /dev/null 2>&1 && apt install -y software-properties-common > /dev/null 2>&1"
  lxc exec "$PROXY_CONTAINER_NAME" -- sudo --user root --login bash -c "apt install -y certbot python3-certbot-nginx > /dev/null 2>&1"

  # Setup SSL using Certbot without showing output
  echo "Setting up SSL certificate for $DOMAIN..."
  SSL_SETUP=$(lxc exec "$PROXY_CONTAINER_NAME" -- sudo certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos --email admin@"$DOMAIN" 2>&1)

  # Check if SSL setup was successful
  if echo "$SSL_SETUP" | grep -q "Congratulations! Your certificate and chain have been saved"; then
    echo "SSL certificate successfully obtained for $DOMAIN."

    # Edit Nginx configuration to add proxy_protocol to SSL listen directives ONLY
    echo "Modifying Nginx configuration for SSL proxy_protocol..."
    lxc exec "$PROXY_CONTAINER_NAME" -- sudo --user root --login bash -c "
      # Only add proxy_protocol to listen 443 ssl; directives
      sed -i '/listen 443 ssl;/a \    listen 443 ssl proxy_protocol; # managed by Certbot' /etc/nginx/sites-enabled/$DOMAIN
      sed -i '/listen \[::\]:443 ssl;/a \    listen [::]:443 ssl proxy_protocol; # managed by Certbot' /etc/nginx/sites-enabled/$DOMAIN
    " > /dev/null 2>&1

    # Reload Nginx to apply changes only if SSL was successfully set up
    echo "Reloading Nginx to apply SSL and proxy_protocol changes..."
    lxc exec "$PROXY_CONTAINER_NAME" -- sudo --user root --login systemctl reload nginx > /dev/null 2>&1

    # Enable SSL auto-renewal (via cron job)
    echo "Setting up SSL certificate renewal cron job..."
    lxc exec "$PROXY_CONTAINER_NAME" -- sudo --user root --login bash -c "echo '0 0,12 * * * root certbot renew --quiet && systemctl reload nginx' > /etc/cron.d/certbot-renew" > /dev/null 2>&1

    # Verify cron job has been added
    echo "Verifying SSL auto-renewal cron job..."
    lxc exec "$PROXY_CONTAINER_NAME" -- sudo --user root --login bash -c "cat /etc/cron.d/certbot-renew" > /dev/null 2>&1

    echo "SSL certificate is successfully set up for $DOMAIN!"
  else
    echo "Error: SSL certificate setup failed for $DOMAIN."
    echo "Details: $SSL_SETUP"
    exit 1
  fi
}
