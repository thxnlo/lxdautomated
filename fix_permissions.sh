#!/bin/bash

# Function to set permissions for WordPress (www-data)
fix_permissions() {
  container=$1
  echo "Fixing permissions for WordPress in container $container..."
  
  # Set ownership of WordPress files to www-data
  lxc exec "$container" -- sudo --user root --login bash -c "sudo chown -R www-data:www-data /var/www/html"
  lxc exec "$container" -- sudo --user root --login bash -c "sudo chmod -R 755 /var/www/html"
}
