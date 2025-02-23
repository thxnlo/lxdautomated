#!/bin/bash

#file: create_wordpress_container.sh

create_wordpress_container() {
  WP_CONTAINER_NAME=$1
  WP_DOMAIN=$2
  DB_CONTAINER_NAME=$3
  ADMIN_USER=$4
  ADMIN_PASS=$5
  ADMIN_EMAIL=$6

  # Check if mysql_credentials.txt exists
  if [[ -f "mysql_credentials.txt" ]]; then
    read -r DB_NAME DB_USER DB_PASSWORD < mysql_credentials.txt
  else
    echo "Error: mysql_credentials.txt not found!"
    read -p "Enter database name: " DB_NAME
    read -p "Enter database username: " DB_USER
    read -s -p "Enter database password: " DB_PASSWORD
    echo ""
  fi

  # Check if WordPress container exists, and if it does, create a new container name with incremental numbering
  COUNTER=1
  NEW_CONTAINER_NAME="$WP_CONTAINER_NAME"
  
  while lxc info "$NEW_CONTAINER_NAME" >/dev/null 2>&1; do
    COUNTER=$((COUNTER + 1))
    if [ $COUNTER -gt 99 ]; then
      COUNTER=1
    fi
    NEW_CONTAINER_NAME="${WP_CONTAINER_NAME}_$(printf "%02d" $COUNTER)"
  done
  
  echo "Creating WordPress container: $NEW_CONTAINER_NAME..."

  # Create WordPress container using Ubuntu 24.04
  if ! lxc launch ubuntu:24.04 "$NEW_CONTAINER_NAME"; then
    echo "Error: Failed to create container $NEW_CONTAINER_NAME"
    return 1
  fi

  # Install dependencies
  echo "Installing dependencies..."
  lxc exec "$NEW_CONTAINER_NAME" -- sudo apt update -y > /dev/null 2>&1
  lxc exec "$NEW_CONTAINER_NAME" -- sudo apt install -y nginx php8.3-fpm php8.3-mysql php8.3-xml php8.3-mbstring mariadb-client curl wget unzip > /dev/null 2>&1

  # Install WP-CLI
  echo "Installing WP-CLI..."
  lxc exec "$NEW_CONTAINER_NAME" -- curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar > /dev/null 2>&1
  lxc exec "$NEW_CONTAINER_NAME" -- chmod +x wp-cli.phar
  lxc exec "$NEW_CONTAINER_NAME" -- sudo mv wp-cli.phar /usr/local/bin/wp

  # Create /var/www/html directory
  lxc exec "$NEW_CONTAINER_NAME" -- sudo mkdir -p /var/www/html
  lxc exec "$NEW_CONTAINER_NAME" -- sudo chown -R www-data:www-data /var/www/html

  # Download and install WordPress
  echo "Downloading WordPress..."
  lxc exec "$NEW_CONTAINER_NAME" -- wp core download --path=/var/www/html --allow-root > /dev/null 2>&1

  # Verify database connectivity before proceeding
  echo "Checking database connection..."
  if ! lxc exec "$DB_CONTAINER_NAME" -- sudo mysql -u"$DB_USER" -p"$DB_PASSWORD" -e "USE $DB_NAME" >/dev/null 2>&1; then
    echo "Error: Unable to connect to MySQL database. Check credentials and try again."
    exit 1
  fi

  # Create wp-config.php
  echo "Configuring WordPress..."
  lxc exec "$NEW_CONTAINER_NAME" -- wp config create --path=/var/www/html --dbname="$DB_NAME" --dbuser="$DB_USER" --dbpass="$DB_PASSWORD" --dbhost="$DB_CONTAINER_NAME.lxd" --allow-root > /dev/null 2>&1

  # Run WordPress installation
  echo "Running WordPress installation..."
  lxc exec "$NEW_CONTAINER_NAME" -- wp core install --path=/var/www/html --url="http://$WP_DOMAIN" --title="My WordPress Site" --admin_user="$ADMIN_USER" --admin_password="$ADMIN_PASS" --admin_email="$ADMIN_EMAIL" --allow-root > /dev/null 2>&1

  # Fix permissions
  fix_permissions "$NEW_CONTAINER_NAME"

  # Configure Nginx
  echo "Configuring Nginx..."
  lxc exec "$NEW_CONTAINER_NAME" -- sudo mkdir -p /etc/nginx/templates
  if [[ ! -f "nginx_wp_config.template" ]]; then
    echo "Error: nginx_wp_config.template not found!"
    return 1
  fi
  lxc file push nginx_wp_config.template "$NEW_CONTAINER_NAME/etc/nginx/templates/nginx_wp_config.template"

  # Generate Nginx config from template
  lxc exec "$NEW_CONTAINER_NAME" -- bash -c "export WP_DOMAIN=$WP_DOMAIN && envsubst '\$WP_DOMAIN' < /etc/nginx/templates/nginx_wp_config.template > /etc/nginx/sites-available/default"

  # Enable Nginx site config
  lxc exec "$NEW_CONTAINER_NAME" -- sudo ln -sf /etc/nginx/sites-available/default /etc/nginx/sites-enabled/

  # Restart Nginx
  lxc exec "$NEW_CONTAINER_NAME" -- sudo systemctl restart nginx

  echo "WordPress setup completed for $WP_DOMAIN in container $NEW_CONTAINER_NAME!"
}