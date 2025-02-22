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

    # Install necessary packages
    echo "Installing Nginx and dependencies in $PROXY_CONTAINER_NAME..."
    lxc exec "$PROXY_CONTAINER_NAME" -- sudo apt update -y
    lxc exec "$PROXY_CONTAINER_NAME" -- sudo apt install -y nginx gettext certbot python3-certbot-nginx || { echo "Failed to install required packages"; exit 1; }
  else
    echo "Proxy container $PROXY_CONTAINER_NAME already exists. Skipping creation."
  fi

  # Ensure the templates directory exists
  echo "Ensuring /etc/nginx/templates directory exists..."
  lxc exec "$PROXY_CONTAINER_NAME" -- sudo mkdir -p /etc/nginx/templates

  # Push nginx_proxy_config.template to the container
  echo "Pushing nginx_proxy_config.template to proxy container..."
  lxc file push nginx_proxy_config.template "$PROXY_CONTAINER_NAME/etc/nginx/templates/nginx_proxy_config.template" || { echo "Failed to push nginx_proxy_config.template"; exit 1; }

  # Ensure template file exists
  echo "Checking if Nginx template file exists..."
  lxc exec "$PROXY_CONTAINER_NAME" -- bash -c "[ -f /etc/nginx/templates/nginx_proxy_config.template ] || { echo 'Missing nginx_proxy_config.template'; exit 1; }"

  # Generate the Nginx config using envsubst
  echo "Generating Nginx configuration from template..."
  lxc exec "$PROXY_CONTAINER_NAME" -- bash -c "export WP_DOMAIN=$WP_DOMAIN WP_CONTAINER_NAME=$WP_CONTAINER_NAME && envsubst < /etc/nginx/templates/nginx_proxy_config.template > /tmp/nginx_temp_config"

  # Validate that the config file was created successfully
  echo "Verifying Nginx configuration file..."
  lxc exec "$PROXY_CONTAINER_NAME" -- bash -c "[ -s /tmp/nginx_temp_config ] || { echo 'Failed to generate Nginx config'; exit 1; }"

  # Move the generated config to sites-available
  echo "Moving Nginx configuration to sites-available..."
  lxc exec "$PROXY_CONTAINER_NAME" -- bash -c "mv /tmp/nginx_temp_config /etc/nginx/sites-available/$WP_DOMAIN"

  # Ensure sites-enabled directory exists
  echo "Ensuring /etc/nginx/sites-enabled directory exists..."
  lxc exec "$PROXY_CONTAINER_NAME" -- sudo mkdir -p /etc/nginx/sites-enabled

  # Remove any existing symlink before creating a new one
  echo "Removing any existing symlink for $WP_DOMAIN in sites-enabled..."
  lxc exec "$PROXY_CONTAINER_NAME" -- sudo rm -f /etc/nginx/sites-enabled/$WP_DOMAIN

  # Enable the site by creating a symlink to the configuration file in sites-available
  echo "Creating symlink for Nginx site in sites-enabled..."
  lxc exec "$PROXY_CONTAINER_NAME" -- bash -c "[ -f /etc/nginx/sites-available/$WP_DOMAIN ] || { echo 'Config file missing, cannot create symlink'; exit 1; }"
  lxc exec "$PROXY_CONTAINER_NAME" -- sudo ln -sf /etc/nginx/sites-available/$WP_DOMAIN /etc/nginx/sites-enabled/

  # Test Nginx configuration before restarting
  echo "Testing Nginx configuration..."
  if ! lxc exec "$PROXY_CONTAINER_NAME" -- sudo nginx -t; then
    echo "Nginx configuration test failed. Check manually."
    exit 1
  fi

  # Restart and enable Nginx service
  echo "Restarting and enabling Nginx service..."
  lxc exec "$PROXY_CONTAINER_NAME" -- sudo systemctl restart nginx
  lxc exec "$PROXY_CONTAINER_NAME" -- sudo systemctl enable nginx || { echo "Failed to enable Nginx on boot"; exit 1; }

  echo "Reverse proxy setup completed for $WP_DOMAIN!"
}
