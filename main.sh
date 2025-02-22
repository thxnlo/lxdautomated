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

# WordPress admin credentials
read -p "Enter the WordPress admin username [admin]: " ADMIN_USER
ADMIN_USER=${ADMIN_USER:-admin}

# Ensure the admin password is not empty
while true; do
  read -s -p "Enter the WordPress admin password: " ADMIN_PASS
  echo
  if [[ -z "$ADMIN_PASS" ]]; then
    echo -e "${RED}⚠️ Admin password cannot be empty. Please try again.${RESET}"
  else
    break
  fi
done

read -p "Enter the WordPress admin email [admin@example.com]: " ADMIN_EMAIL
ADMIN_EMAIL=${ADMIN_EMAIL:-admin@example.com}

# Extract WordPress site name from domain
WP_SITE_NAME=$(echo "$DOMAIN" | cut -d'.' -f1)

# ===========================
# Step 1: Setup MySQL Container
# ===========================
echo -e "${YELLOW}📦 Setting up MySQL container: $DB_CONTAINER_NAME...${RESET}"
create_mysql_container "$DB_CONTAINER_NAME" "$WP_SITE_NAME" "$WP_CONTAINER_NAME"
if [[ $? -ne 0 ]]; then
  echo -e "${RED}❌ MySQL setup failed. Please check the logs and try again.${RESET}"
  exit 1
fi
echo -e "${GREEN}✅ MySQL setup complete!${RESET}"

# ===========================
# Step 2: Setup WordPress Container
# ===========================
echo -e "${YELLOW}🌐 Setting up WordPress container: $WP_CONTAINER_NAME...${RESET}"
create_wordpress_container "$WP_CONTAINER_NAME" "$DOMAIN" "$DB_CONTAINER_NAME" "$ADMIN_USER" "$ADMIN_PASS" "$ADMIN_EMAIL"
if [[ $? -ne 0 ]]; then
  echo -e "${RED}❌ WordPress setup failed. Please check the logs and try again.${RESET}"
  exit 1
fi
echo -e "${GREEN}✅ WordPress setup complete!${RESET}"

# ===========================
# Step 3: Setup Proxy
# ===========================
echo -e "${YELLOW}🔧 Configuring Proxy...${RESET}"
setup_proxy "proxy" "$WP_CONTAINER_NAME" "$DOMAIN"
if [[ $? -ne 0 ]]; then
  echo -e "${RED}❌ Proxy configuration failed. Please check the logs and try again.${RESET}"
  exit 1
fi
echo -e "${GREEN}✅ Proxy setup complete!${RESET}"

# ===========================
# Step 4: Setup SSL
# ===========================
echo -e "${YELLOW}🔒 Setting up SSL for $DOMAIN...${RESET}"
setup_ssl "$DOMAIN" "$WP_CONTAINER_NAME" "proxy"
if [[ $? -ne 0 ]]; then
  echo -e "${RED}❌ SSL setup failed. Please check the logs and try again.${RESET}"
  exit 1
fi
echo -e "${GREEN}✅ SSL setup complete!${RESET}"

# Final Message
echo -e "${BOLD}${CYAN}"
echo "========================================"
echo " 🎉 WordPress site is live at: https://$DOMAIN 🎉"
echo "========================================"
echo -e "${RESET}"

# Clear sensitive variables
unset ADMIN_USER ADMIN_PASS ADMIN_EMAIL
unset WP_CONTAINER_NAME DOMAIN DB_CONTAINER_NAME WP_SITE_NAME
