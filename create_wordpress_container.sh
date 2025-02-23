#!/bin/bash

#file: create_wordpress_container.sh

create_wordpress_container() {
    local WP_CONTAINER_NAME="$1"
    local WP_DOMAIN="$2"
    local DB_CONTAINER_NAME="$3"
    local ADMIN_USER="$4"
    local ADMIN_PASS="$5"
    local ADMIN_EMAIL="$6"

    # Input validation
    if [ -z "$WP_CONTAINER_NAME" ] || [ -z "$WP_DOMAIN" ] || [ -z "$DB_CONTAINER_NAME" ]; then
        echo "Error: Missing required parameters"
        echo "Usage: create_wordpress_container WP_CONTAINER_NAME WP_DOMAIN DB_CONTAINER_NAME ADMIN_USER ADMIN_PASS ADMIN_EMAIL"
        return 1
    fi

    # Debug output
    echo "Debug: Creating WordPress container with:"
    echo "Container Name: $WP_CONTAINER_NAME"
    echo "Domain: $WP_DOMAIN"
    echo "DB Container: $DB_CONTAINER_NAME"

    # Read database credentials
    if [[ -f "mysql_credentials.txt" ]]; then
        if ! read -r DB_NAME DB_USER DB_PASSWORD < mysql_credentials.txt; then
            echo "Error: Failed to read mysql_credentials.txt"
            return 1
        fi
    else
        echo "Error: mysql_credentials.txt not found!"
        read -p "Enter database name: " DB_NAME
        read -p "Enter database username: " DB_USER
        read -s -p "Enter database password: " DB_PASSWORD
        echo ""
    fi

    # Create container with incremental naming
    COUNTER=1
    NEW_CONTAINER_NAME="$WP_CONTAINER_NAME"
    
    while lxc info "$NEW_CONTAINER_NAME" >/dev/null 2>&1; do
        COUNTER=$((COUNTER + 1))
        if [ $COUNTER -gt 99 ]; then
            echo "Error: Maximum container count reached"
            return 1
        fi
        NEW_CONTAINER_NAME="${WP_CONTAINER_NAME}$(printf "%02d" $COUNTER)"
    done
    
    echo "Creating WordPress container: $NEW_CONTAINER_NAME..."

    # Create container with error checking
    if ! lxc launch ubuntu:24.04 "$NEW_CONTAINER_NAME"; then
        echo "Error: Failed to create container $NEW_CONTAINER_NAME"
        return 1
    fi

    # Wait for container to be ready
    echo "Waiting for container to be ready..."
    sleep 10

    # Install dependencies with progress feedback
    echo "Installing dependencies..."
    if ! lxc exec "$NEW_CONTAINER_NAME" -- bash -c "
        export DEBIAN_FRONTEND=noninteractive
        apt update -y && 
        apt install -y nginx php8.3-fpm php8.3-mysql php8.3-xml php8.3-mbstring mariadb-client curl wget unzip
    "; then
        echo "Error: Failed to install dependencies"
        return 1
    fi

    # Install WP-CLI with error checking
    echo "Installing WP-CLI..."
    if ! lxc exec "$NEW_CONTAINER_NAME" -- bash -c "
        curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar &&
        chmod +x wp-cli.phar &&
        mv wp-cli.phar /usr/local/bin/wp
    "; then
        echo "Error: Failed to install WP-CLI"
        return 1
    fi

    # Set up WordPress directory
    echo "Setting up WordPress directory..."
    if ! lxc exec "$NEW_CONTAINER_NAME" -- bash -c "
        mkdir -p /var/www/html &&
        chown -R www-data:www-data /var/www/html
    "; then
        echo "Error: Failed to set up WordPress directory"
        return 1
    fi

    # Download WordPress
    echo "Downloading WordPress..."
    if ! lxc exec "$NEW_CONTAINER_NAME" -- wp core download --path=/var/www/html --allow-root; then
        echo "Error: Failed to download WordPress"
        return 1
    fi

    # Check database connection
    echo "Verifying database connection..."
    if ! lxc exec "$NEW_CONTAINER_NAME" -- mysql -h"$DB_CONTAINER_NAME".lxd -u"$DB_USER" -p"$DB_PASSWORD" "$DB_NAME" -e "SELECT 1;" >/dev/null 2>&1; then
        echo "Error: Cannot connect to database. Please check credentials and connectivity"
        return 1
    fi

    # Create wp-config.php
    echo "Creating WordPress configuration..."
    if ! lxc exec "$NEW_CONTAINER_NAME" -- wp config create \
        --path=/var/www/html \
        --dbname="$DB_NAME" \
        --dbuser="$DB_USER" \
        --dbpass="$DB_PASSWORD" \
        --dbhost="$DB_CONTAINER_NAME.lxd" \
        --allow-root; then
        echo "Error: Failed to create wp-config.php"
        return 1
    fi

    # Install WordPress
    echo "Installing WordPress..."
    if ! lxc exec "$NEW_CONTAINER_NAME" -- wp core install \
        --path=/var/www/html \
        --url="https://$WP_DOMAIN" \
        --title="$WP_DOMAIN" \
        --admin_user="$ADMIN_USER" \
        --admin_password="$ADMIN_PASS" \
        --admin_email="$ADMIN_EMAIL" \
        --allow-root; then
        echo "Error: Failed to install WordPress"
        return 1
    fi

    # Fix permissions
    echo "Setting correct permissions..."
    if type fix_permissions >/dev/null 2>&1; then
        fix_permissions "$NEW_CONTAINER_NAME"
    else
        echo "Warning: fix_permissions function not found, skipping..."
    fi

    # Configure Nginx
    echo "Configuring Nginx..."
    if [[ ! -f "nginx_wp_config.template" ]]; then
        echo "Error: nginx_wp_config.template not found!"
        return 1
    fi

    if ! lxc exec "$NEW_CONTAINER_NAME" -- mkdir -p /etc/nginx/templates; then
        echo "Error: Failed to create Nginx templates directory"
        return 1
    fi

    if ! lxc file push nginx_wp_config.template "$NEW_CONTAINER_NAME/etc/nginx/templates/"; then
        echo "Error: Failed to push Nginx template"
        return 1
    fi

    # Generate and validate Nginx config
    if ! lxc exec "$NEW_CONTAINER_NAME" -- bash -c "
        export WP_DOMAIN='$WP_DOMAIN'
        envsubst '\$WP_DOMAIN' < /etc/nginx/templates/nginx_wp_config.template > /etc/nginx/sites-available/default &&
        ln -sf /etc/nginx/sites-available/default /etc/nginx/sites-enabled/ &&
        nginx -t
    "; then
        echo "Error: Invalid Nginx configuration"
        return 1
    fi

    # Restart Nginx
    if ! lxc exec "$NEW_CONTAINER_NAME" -- systemctl restart nginx; then
        echo "Error: Failed to restart Nginx"
        return 1
    fi

    echo "✅ WordPress setup completed successfully!"
    echo "Container Name: $NEW_CONTAINER_NAME"
    echo "WordPress URL: https://$WP_DOMAIN"
    echo "Admin URL: https://$WP_DOMAIN/wp-admin"
    echo "Admin Username: $ADMIN_USER"
    
    # Export the new container name for other scripts to use
    export WP_CONTAINER_NAME="$NEW_CONTAINER_NAME"
    return 0
}