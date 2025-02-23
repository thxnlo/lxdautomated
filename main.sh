#!/bin/bash

# ===========================
# WordPress Auto Deployment
# ===========================

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m' # Reset color

# Fancy Header
echo -e "${CYAN}"
echo "========================================"
echo " 🚀 Auto LXD based WP by thxnlo 🚀"
echo "========================================"
echo -e "${RESET}"

# Source modules
source ./set_root_password_db.sh
source ./fix_permissions.sh
source ./create_mysql_container.sh
source ./create_wordpress_container.sh
source ./setup_proxy.sh
source ./setup_ssl.sh

# Prompt for user inputs
echo -e "${BOLD}${BLUE}Enter WordPress Configuration Details:${RESET}"

read -p "Enter the WordPress container name [wordpress-site]: " WP_CONTAINER_NAME
WP_CONTAINER_NAME=${WP_CONTAINER_NAME:-wordpress-site}

read -p "Enter the domain name for WordPress [example.com]: " DOMAIN
DOMAIN=${DOMAIN:-example.com}

# Hardcode DB container name to "db"
DB_CONTAINER_NAME="db"

# Generate a secure random root password
generate_secure_password() {
  # This will generate a secure password with uppercase, lowercase, numbers, and special characters
  tr -dc 'A-Za-z0-9_@#%&*+=!~' </dev/urandom | head -c 20
}

# Check if MariaDB is already installed
if ! lxc exec "$DB_CONTAINER_NAME" -- sudo --user root --login bash -c "systemctl is-active --quiet mariadb"; then
  # MariaDB is not installed, so generate a new root password
  DB_ROOT_PASSWORD=$(generate_secure_password)
  echo "Generated MySQL root password: $DB_ROOT_PASSWORD"
else
  # MariaDB is already installed, use an existing password (you may want to handle this differently)
  echo "MariaDB is already installed. Using the existing root password."
  # You can either prompt the user for an existing root password or retrieve it securely.
  DB_ROOT_PASSWORD="existingRootPassword"  # You may choose to securely store/retrieve this
fi

# WordPress admin credentials
read -p "Enter the WordPress admin username [admin]: " ADMIN_USER
ADMIN_USER=${ADMIN_USER:-admin}

read -p "Enter the WordPress admin password: " ADMIN_PASS

read -p "Enter the WordPress admin email [admin@example.com]: " ADMIN_EMAIL
ADMIN_EMAIL=${ADMIN_EMAIL:-admin@example.com}

# Extract WordPress site name from domain
WP_SITE_NAME=$(echo "$DOMAIN" | cut -d'.' -f1)

# ===========================
# Step 1: Setup MySQL Container
# ===========================
echo -e "${YELLOW}📦 Setting up MySQL container...${RESET}"
create_mysql_container "$DB_CONTAINER_NAME" "$DB_ROOT_PASSWORD" "$WP_SITE_NAME" "$WP_CONTAINER_NAME"
echo -e "${GREEN}✅ MySQL setup complete!${RESET}"

# ===========================
# Step 2: Setup WordPress Container
# ===========================
echo -e "${YELLOW}🌐 Setting up WordPress container...${RESET}"
create_wordpress_container "$WP_CONTAINER_NAME" "$DOMAIN" "$DB_CONTAINER_NAME" "$ADMIN_USER" "$ADMIN_PASS" "$ADMIN_EMAIL"
echo -e "${GREEN}✅ WordPress setup complete!${RESET}"

# ===========================
# Step 3: Setup Proxy
# ===========================
echo -e "${YELLOW}🔧 Configuring Proxy...${RESET}"
setup_proxy "proxy" "$WP_CONTAINER_NAME" "$DOMAIN"
echo -e "${GREEN}✅ Proxy setup complete!${RESET}"

# ===========================
# Step 4: Setup SSL
# ===========================
echo -e "${YELLOW}🔒 Setting up SSL for $DOMAIN...${RESET}"
setup_ssl "$DOMAIN"
echo -e "${GREEN}✅ SSL setup complete!${RESET}"

# Final Message
echo -e "${BOLD}${CYAN}"
echo "========================================"
echo " 🎉 WordPress site is live at: https://$DOMAIN 🎉"
echo "========================================"
echo -e "${RESET}"

# Clear sensitive variables
unset DB_ROOT_PASSWORD ADMIN_USER ADMIN_PASS ADMIN_EMAIL
unset WP_CONTAINER_NAME DOMAIN DB_CONTAINER_NAME WP_SITE_NAME
