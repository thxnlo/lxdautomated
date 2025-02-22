#!/bin/bash

setup_proxy() {
  PROXY_CONTAINER_NAME=$1
  WP_CONTAINER_NAME=$2
  WP_DOMAIN=$3

  # Check if proxy container exists
  if ! lxc list | grep -q "$PROXY_CONTAINER_NAME"; then
    echo "Creating proxy container..."

    # Create Proxy container using Ubuntu 24.04
    lxc launch ubuntu:24.04 "$PROXY_CONTAINER_NAME"

    # Install Nginx in proxy container without showing output
    echo "Installing Nginx in $PROXY_CONTAINER_NAME..."
    lxc exec "$PROXY_CONTAINER_NAME" -- sudo --user root --login bash -c "apt update -y > /dev/null 2>&1 && apt install -y nginx > /dev/null 2>&1"

    # Install Certbot and Nginx plugin for SSL without showing output
    echo "Installing Certbot and Nginx plugin for SSL..."
    lxc exec "$PROXY_CONTAINER_NAME" -- sudo --user root --login bash -c "apt install -y certbot python3-certbot-nginx > /dev/null 2>&1"

    # Ensure the templates directory exists
    echo "Ensuring /etc/nginx/templates directory exists..."
    lxc exec "$PROXY_CONTAINER_NAME" -- sudo --user root --login bash -c "mkdir -p /etc/nginx/templates > /dev/null 2>&1"

    # Push nginx_proxy_config.template to the container
    echo "Pushing nginx_proxy_config.template to proxy container..."
    lxc file push nginx_proxy_config.template "$PROXY_CONTAINER_NAME/etc/nginx/templates/nginx_proxy_config.template" > /dev/null 2>&1

    # Debug: Print the variables inside the container to ensure they are set
    echo "Debugging: Verifying WP_DOMAIN and WP_CONTAINER_NAME variables inside the container..."
    lxc exec "$PROXY_CONTAINER_NAME" -- bash -c "echo WP_DOMAIN=$WP_DOMAIN WP_CONTAINER_NAME=$WP_CONTAINER_NAME"

    # Use envsubst to replace variables in the template and generate the Nginx config file
    echo "Generating Nginx configuration from template..."
    lxc exec "$PROXY_CONTAINER_NAME" -- bash -c "export WP_DOMAIN=$WP_DOMAIN WP_CONTAINER_NAME=$WP_CONTAINER_NAME && envsubst < /etc/nginx/templates/nginx_proxy_config.template > /etc/nginx/sites-available/$WP_DOMAIN > /dev/null 2>&1"

    # Ensure the directory for sites-enabled exists
    echo "Ensuring /etc/nginx/sites-enabled exists..."
    lxc exec "$PROXY_CONTAINER_NAME" -- sudo --user root --login bash -c "mkdir -p /etc/nginx/sites-enabled > /dev/null 2>&1"

    # Remove any existing symlink in sites-enabled before creating a new one
    echo "Removing any existing symlink for $WP_DOMAIN in sites-enabled..."
    lxc exec "$PROXY_CONTAINER_NAME" -- sudo --user root --login bash -c "rm -f /etc/nginx/sites-enabled/$WP_DOMAIN > /dev/null 2>&1"

    # Enable the site by creating a symlink to the configuration file in sites-available
    echo "Creating symlink for Nginx site in sites-enabled..."
    lxc exec "$PROXY_CONTAINER_NAME" -- sudo --user root --login bash -c "ln -sf /etc/nginx/sites-available/$WP_DOMAIN /etc/nginx/sites-enabled/ > /dev/null 2>&1"

    # Test Nginx configuration before restarting (output hidden unless there’s an error)
    echo "Testing Nginx configuration..."
    if ! lxc exec "$PROXY_CONTAINER_NAME" -- sudo --user root --login bash -c "nginx -t > /dev/null 2>&1"; then
      echo "Nginx configuration test failed. Check manually."
    fi

    # Restart Nginx service in proxy container to apply changes
    echo "Restarting Nginx service..."
    lxc exec "$PROXY_CONTAINER_NAME" -- sudo --user root --login systemctl restart nginx > /dev/null 2>&1

    # Enable Nginx service to start on boot
    echo "Enabling Nginx to start on boot..."
    lxc exec "$PROXY_CONTAINER_NAME" -- sudo --user root --login systemctl enable nginx > /dev/null 2>&1

    echo "Reverse proxy setup completed for $WP_DOMAIN!"

  else
    echo "Proxy container $PROXY_CONTAINER_NAME already exists. Skipping creation."
  fi
}
