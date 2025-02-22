#!/bin/bash

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

  # Check if WordPress container exists
  if lxc info "$WP_CONTAINER_NAME" >/dev/null 2>&1; then
    echo "Container $WP_CONTAINER_NAME already exists. Skipping creation."
    return
  fi

  echo "Creating WordPress container: $WP_CONTAINER_NAME..."

  # Create WordPress container using Ubuntu 24.04
  lxc launch ubuntu:24.04 "$WP_CONTAINER_NAME"

  # Install dependencies
  echo "Installing dependencies..."
  lxc exec "$WP_CONTAINER_NAME" -- sudo apt update -y > /dev/null 2>&1
  lxc exec "$WP_CONTAINER_NAME" -- sudo apt install -y nginx php8.3-fpm php8.3-mysql php8.3-xml php8.3-mbstring mariadb-client curl wget unzip > /dev/null 2>&1

  # Install WP-CLI
  echo "Installing WP-CLI..."
  lxc exec "$WP_CONTAINER_NAME" -- curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar > /dev/null 2>&1
  lxc exec "$WP_CONTAINER_NAME" -- chmod +x wp-cli.phar
  lxc exec "$WP_CONTAINER_NAME" -- sudo mv wp-cli.phar /usr/local/bin/wp

  # Create /var/www/html directory
  lxc exec "$WP_CONTAINER_NAME" -- sudo mkdir -p /var/www/html
  lxc exec "$WP_CONTAINER_NAME" -- sudo chown -R www-data:www-data /var/www/html

  # Download and install WordPress
  echo "Downloading WordPress..."
  lxc exec "$WP_CONTAINER_NAME" -- wp core download --path=/var/www/html --allow-root > /dev/null 2>&1

  # Verify database connectivity before proceeding
  echo "Checking database connection..."
  if ! lxc exec "$DB_CONTAINER_NAME" -- sudo mysql -u"$DB_USER" -p"$DB_PASSWORD" -e "USE $DB_NAME" >/dev/null 2>&1; then
    echo "Error: Unable to connect to MySQL database. Check credentials and try again."
    exit 1
  fi

  # Create wp-config.php
  echo "Configuring WordPress..."
  lxc exec "$WP_CONTAINER_NAME" -- wp config create --path=/var/www/html --dbname="$DB_NAME" --dbuser="$DB_USER" --dbpass="$DB_PASSWORD" --dbhost="$DB_CONTAINER_NAME.lxd" --allow-root > /dev/null 2>&1

  # Run WordPress installation
  echo "Running WordPress installation..."
  lxc exec "$WP_CONTAINER_NAME" -- wp core install --path=/var/www/html --url="http://$WP_DOMAIN" --title="My WordPress Site" --admin_user="$ADMIN_USER" --admin_password="$ADMIN_PASS" --admin_email="$ADMIN_EMAIL" --allow-root > /dev/null 2>&1

  # Fix permissions
  fix_permissions "$WP_CONTAINER_NAME"

  # Configure Nginx
  echo "Configuring Nginx..."
  lxc exec "$WP_CONTAINER_NAME" -- sudo mkdir -p /etc/nginx/templates
  lxc file push nginx_wp_config.template "$WP_CONTAINER_NAME/etc/nginx/templates/nginx_wp_config.template"

  # Generate Nginx config from template
  lxc exec "$WP_CONTAINER_NAME" -- bash -c "export WP_DOMAIN=$WP_DOMAIN && envsubst '\$WP_DOMAIN' < /etc/nginx/templates/nginx_wp_config.template > /etc/nginx/sites-available/default"

  # Enable Nginx site config
  lxc exec "$WP_CONTAINER_NAME" -- sudo ln -sf /etc/nginx/sites-available/default /etc/nginx/sites-enabled/

  # Restart Nginx
  lxc exec "$WP_CONTAINER_NAME" -- sudo systemctl restart nginx

  echo "WordPress setup completed for $WP_DOMAIN!"
}
