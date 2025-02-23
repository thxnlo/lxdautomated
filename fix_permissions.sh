#!/bin/bash

# Function to set permissions for WordPress (www-data)
fix_permissions() {
  container=$1
  echo "Fixing permissions for WordPress in container $container..."

  # Set ownership of WordPress files to www-data
  lxc exec "$container" -- sudo chown -R www-data:www-data /var/www/html

  # Set directory permissions to 755
  lxc exec "$container" -- sudo find /var/www/html -type d -exec chmod 755 {} \;

  # Set file permissions to 644
  lxc exec "$container" -- sudo find /var/www/html -type f -exec chmod 644 {} \;
}
