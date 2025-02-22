#!/bin/bash

# ===========================
# MySQL Container Creation Script
# ===========================

# Colors for styling
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

# Function to display a spinner while waiting
spin() {
  local pid=$!
  local delay=0.1
  local spinstr='|/-\' 
  while ps -p $pid > /dev/null 2>&1; do
    printf " [%c]  " "$spinstr"
    spinstr=$(echo $spinstr | tail -c 2)${spinstr%"${spinstr%"${spinstr%"${spinstr%"${spinstr:0:1}"}`" }
    sleep $delay
    printf "\r"
  done
}

# Function to generate a random password
generate_random_password() {
  tr -dc A-Za-z0-9 </dev/urandom | head -c 16
}

# Function to generate a unique database name
generate_unique_db_name() {
  local base_name=$1
  local suffix=1
  local unique_name="${base_name}_db"

  # Check if the database name already exists and append a number to avoid overlap
  while lxc exec "$DB_CONTAINER_NAME" -- sudo --user root --login bash -c "sudo mysql -e 'SHOW DATABASES LIKE \"$unique_name\";' | grep -q \"$unique_name\""; do
    unique_name="${base_name}_db_${suffix}"
    ((suffix++))
  done

  echo "$unique_name"
}

# Function to generate a unique database user
generate_unique_db_user() {
  local base_user=$1
  local suffix=1
  local unique_user="${base_user}_user"

  while lxc exec "$DB_CONTAINER_NAME" -- sudo --user root --login bash -c "sudo mysql -e 'SELECT User FROM mysql.user WHERE User=\"$unique_user\";' | grep -q \"$unique_user\""; do
    unique_user="${base_user}_user_${suffix}"
    ((suffix++))
  done

  echo "$unique_user"
}

# Function to create MySQL container and configure it
create_mysql_container() {
  DB_CONTAINER_NAME=$1
  DB_ROOT_PASSWORD=$2
  WP_SITE_NAME=$3  
  WP_CONTAINER_NAME=$4

  echo -e "${CYAN}========================================${RESET}"
  echo -e "${CYAN}🚀 MySQL Container Setup in Progress 🚀${RESET}"
  echo -e "${CYAN}========================================${RESET}"

  # Check if MySQL container already exists
  echo -e "${YELLOW}🔍 Checking for existing MySQL container: $DB_CONTAINER_NAME...${RESET}"

  if ! lxc info "$DB_CONTAINER_NAME" >/dev/null 2>&1; then
    echo -e "${BLUE}Creating MySQL container: $DB_CONTAINER_NAME...${RESET}"
    lxc launch ubuntu:24.04 "$DB_CONTAINER_NAME" & spin

    # Set root password
    echo -e "${GREEN}🔑 Setting root password...${RESET}"
    lxc exec "$DB_CONTAINER_NAME" -- sudo --user root --login bash -c "echo 'root:$DB_ROOT_PASSWORD' | chpasswd"

    # Install MariaDB
    echo -e "${GREEN}📦 Installing MariaDB...${RESET}"
    lxc exec "$DB_CONTAINER_NAME" -- sudo --user root --login bash -c "sudo apt update -y > /dev/null 2>&1 && sudo apt install -y mariadb-server > /dev/null 2>&1" & spin
    lxc exec "$DB_CONTAINER_NAME" -- sudo --user root --login bash -c "sudo systemctl start mariadb > /dev/null 2>&1"

    # Configure MariaDB to bind to 0.0.0.0
    echo -e "${YELLOW}🔧 Configuring MariaDB to bind to 0.0.0.0...${RESET}"
    lxc exec "$DB_CONTAINER_NAME" -- sudo --user root --login bash -c "sudo sed -i 's/^bind-address.*/bind-address = 0.0.0.0/' /etc/mysql/mariadb.conf.d/50-server.cnf"
    lxc exec "$DB_CONTAINER_NAME" -- sudo --user root --login bash -c "sudo systemctl restart mariadb > /dev/null 2>&1"

    # Run secure installation
    echo -e "${YELLOW}🔒 Running MariaDB secure installation...${RESET}"
    lxc exec "$DB_CONTAINER_NAME" -- sudo --user root --login bash -c "
      sudo mysql -e 'UPDATE mysql.user SET password = PASSWORD(\"$DB_ROOT_PASSWORD\") WHERE User = \"root\"';
      sudo mysql -e 'DELETE FROM mysql.user WHERE User = \"\"';
      sudo mysql -e 'DELETE FROM mysql.db WHERE Db = \"test\" OR Db = \"test_%\"';
      sudo mysql -e 'FLUSH PRIVILEGES';
    "
  else
    echo -e "${GREEN}MySQL container $DB_CONTAINER_NAME already exists.${RESET}"
  fi

  # Generate unique database name and user
  DB_NAME=$(generate_unique_db_name "$WP_SITE_NAME")
  DB_USER=$(generate_unique_db_user "$WP_SITE_NAME")
  DB_PASSWORD=$(generate_random_password)

  # Display generated values for debugging
  echo -e "${CYAN}Generated Database Details:${RESET}"
  echo -e "${GREEN}Database Name: $DB_NAME${RESET}"
  echo -e "${GREEN}Database User: $DB_USER${RESET}"
  echo -e "${GREEN}Database Password: $DB_PASSWORD${RESET}"

  # Create database and user (use `IF NOT EXISTS` to ensure they are created only if not already present)
  echo -e "${YELLOW}🛠 Creating database and user...${RESET}"
  lxc exec "$DB_CONTAINER_NAME" -- sudo --user root --login bash -c "sudo mysql -e \"CREATE DATABASE IF NOT EXISTS $DB_NAME;\""
  lxc exec "$DB_CONTAINER_NAME" -- sudo --user root --login bash -c "sudo mysql -e \"CREATE USER IF NOT EXISTS '$DB_USER'@'%' IDENTIFIED BY '$DB_PASSWORD';\""
  lxc exec "$DB_CONTAINER_NAME" -- sudo --user root --login bash -c "sudo mysql -e \"GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'%';\""
  lxc exec "$DB_CONTAINER_NAME" -- sudo --user root --login bash -c "sudo mysql -e \"FLUSH PRIVILEGES;\""

  # Save credentials to a separate file for the WordPress site
  CREDENTIALS_FILE="./mysql_credentials_${WP_SITE_NAME}.txt"
  echo -e "${YELLOW}📄 Saving credentials to ${CREDENTIALS_FILE}...${RESET}"
  echo "$DB_NAME $DB_USER $DB_PASSWORD" > "$CREDENTIALS_FILE"

  # Clear sensitive variables after saving
  unset DB_NAME DB_USER DB_PASSWORD

  # Copy custom MariaDB configuration
  echo -e "${YELLOW}🔧 Copying custom MariaDB configuration...${RESET}"
  lxc file push ./custom_mariadb.cnf "$DB_CONTAINER_NAME"/etc/mysql/mariadb.conf.d/50-server.cnf
  lxc exec "$DB_CONTAINER_NAME" -- sudo --user root --login bash -c "sudo systemctl restart mariadb > /dev/null 2>&1"

  # Final message
  echo -e "${GREEN}✅ MySQL setup complete!${RESET}"
}

# Example usage (you can replace these with actual arguments passed to the script)
# create_mysql_container "mysql_container" "root_password" "wp_site" "wordpress_container"
