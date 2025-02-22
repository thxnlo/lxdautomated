#!/bin/bash

setup_proxy() {
  PROXY_CONTAINER_NAME=$1
  WP_CONTAINER_NAME=$2
  WP_DOMAIN=$3

  # Check if proxy container exists
  if ! lxc list | grep -q "$PROXY_CONTAINER_NAME"; then
    echo "Creating proxy container..."

    # Create Proxy container using Ubuntu 24.04
    lxc launch ubuntu:24.04 "$PROXY_CONTAINER_NAME" || { echo "Failed to create proxy container"; exit 1; }

    # Install Nginx in proxy container without showing output
    echo "Installing Nginx in $PROXY_CONTAINER_NAME..."
    lxc exec "$PROXY_CONTAINER_NAME" -- sudo --user root --login bash -c "apt update -y > /dev/null 2>&1 && apt install -y nginx > /dev/null 2>&1" || { echo "Failed to install Nginx"; exit 1; }

    # Install Certbot and Nginx plugin for SSL without showing output
    echo "Installing Certbot and Nginx plugin for SSL..."
    lxc exec "$PROXY_CONTAINER_NAME" -- sudo --user root --login bash -c "apt install -y certbot python3-certbot-nginx > /dev/null 2>&1" || { echo "Failed to install Certbot"; exit 1; }

    # Ensure the templates directory exists
    echo "Ensuring /etc/nginx/templates directory exists..."
    lxc exec "$PROXY_CONTAINER_NAME" -- sudo --user root --login bash -c "mkdir -p /etc/nginx/templates" || { echo "Failed to create /etc/nginx/templates directory"; exit 1; }

    # Push nginx_proxy_config.template to the container
    echo "Pushing nginx_proxy_config.template to proxy container..."
    lxc file push nginx_proxy_config.template "$PROXY_CONTAINER_NAME/etc/nginx/templates/nginx_proxy_config.template" || { echo "Failed to push nginx_proxy_config.template"; exit 1; }

    # Debug: Print the variables inside the container to ensure they are set
    echo "Debugging: Verifying WP_DOMAIN and WP_CONTAINER_NAME variables inside the container..."
    lxc exec "$PROXY_CONTAINER_NAME" -- bash -c "echo WP_DOMAIN=$WP_DOMAIN WP_CONTAINER_NAME=$WP_CONTAINER_NAME" || { echo "Failed to verify environment variables"; exit 1; }

    # Use envsubst to replace variables in the template and generate the Nginx config file
    echo "Generating Nginx configuration from template..."
    lxc exec "$PROXY_CONTAINER_NAME" -- bash -c "export WP_DOMAIN=$WP_DOMAIN WP_CONTAINER_NAME=$WP_CONTAINER_NAME && envsubst < /etc/nginx/templates/nginx_proxy_config.template > /etc/nginx/sites-available/$WP_DOMAIN" || { echo "Failed to generate Nginx configuration"; exit 1; }

    lxc exec proxy -- bash -c "export WP_DOMAIN=testvps.localhost WP_CONTAINER_NAME=newsite3 && envsubst < /etc/nginx/templates/nginx_proxy_config.template > /etc/nginx/sites-available/$WP_DOMAIN" || { echo "Failed to generate Nginx configuration"; exit 1; }



    # Ensure the directory for sites-enabled exists
    echo "Ensuring /etc/nginx/sites-enabled exists..."
    lxc exec "$PROXY_CONTAINER_NAME" -- sudo --user root --login bash -c "mkdir -p /etc/nginx/sites-enabled" || { echo "Failed to create /etc/nginx/sites-enabled directory"; exit 1; }

    # Remove any existing symlink in sites-enabled before creating a new one
    echo "Removing any existing symlink for $WP_DOMAIN in sites-enabled..."
    lxc exec "$PROXY_CONTAINER_NAME" -- sudo --user root --login bash -c "rm -f /etc/nginx/sites-enabled/$WP_DOMAIN" || { echo "Failed to remove existing symlink"; exit 1; }

    # Enable the site by creating a symlink to the configuration file in sites-available
    echo "Creating symlink for Nginx site in sites-enabled..."
    lxc exec "$PROXY_CONTAINER_NAME" -- sudo --user root --login bash -c "ln -sf /etc/nginx/sites-available/$WP_DOMAIN /etc/nginx/sites-enabled/" || { echo "Failed to create symlink"; exit 1; }

    # Test Nginx configuration before restarting (output hidden unless there’s an error)
    echo "Testing Nginx configuration..."
    if ! lxc exec "$PROXY_CONTAINER_NAME" -- sudo --user root --login bash -c "nginx -t"; then
      echo "Nginx configuration test failed. Check manually."
      exit 1
    fi

    # Restart Nginx service in proxy container to apply changes
    echo "Restarting Nginx service..."
    lxc exec "$PROXY_CONTAINER_NAME" -- sudo --user root --login systemctl restart nginx || { echo "Failed to restart Nginx"; exit 1; }

    # Enable Nginx service to start on boot
    echo "Enabling Nginx to start on boot..."
    lxc exec "$PROXY_CONTAINER_NAME" -- sudo --user root --login systemctl enable nginx || { echo "Failed to enable Nginx service on boot"; exit 1; }

    echo "Reverse proxy setup completed for $WP_DOMAIN!"

  else
    echo "Proxy container $PROXY_CONTAINER_NAME already exists. Skipping creation."
  fi
}
