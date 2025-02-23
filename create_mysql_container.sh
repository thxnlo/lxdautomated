#!/bin/bash

generate_random_password() {
  tr -dc A-Za-z0-9 </dev/urandom | head -c 16
}

generate_unique_db_name() {
  local base_name=$1
  local suffix=1
  local unique_name="${base_name}_db"

  while lxc exec "$DB_CONTAINER_NAME" -- sudo --user root --login bash -c "sudo mysql -e 'SHOW DATABASES LIKE \"$unique_name\";' | grep -q \"$unique_name\""; do
    unique_name="${base_name}_db_${suffix}"
    ((suffix++))
  done

  echo "$unique_name"
}

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

create_mysql_container() {
  DB_CONTAINER_NAME=$1
  DB_ROOT_PASSWORD=$2
  WP_SITE_NAME=$3  
  WP_CONTAINER_NAME=$4

  echo "Checking for existing MySQL container: $DB_CONTAINER_NAME..."

  if ! lxc info "$DB_CONTAINER_NAME" >/dev/null 2>&1; then
    echo "Creating MySQL container: $DB_CONTAINER_NAME..."
    lxc launch ubuntu:24.04 "$DB_CONTAINER_NAME"

    echo "Checking if MariaDB is installed..."
    if ! lxc exec "$DB_CONTAINER_NAME" -- which mariadb >/dev/null 2>&1; then
      echo "MariaDB is not installed, installing MariaDB..."
      lxc exec "$DB_CONTAINER_NAME" -- sudo --user root --login bash -c "sudo apt update -y > /dev/null 2>&1 && sudo apt install -y mariadb-server > /dev/null 2>&1"
      lxc exec "$DB_CONTAINER_NAME" -- sudo --user root --login bash -c "sudo systemctl start mariadb > /dev/null 2>&1"

      echo "Configuring MariaDB to bind to 0.0.0.0..."
      lxc exec "$DB_CONTAINER_NAME" -- sudo --user root --login bash -c "sudo sed -i 's/^bind-address.*/bind-address = 0.0.0.0/' /etc/mysql/mariadb.conf.d/50-server.cnf"
      lxc exec "$DB_CONTAINER_NAME" -- sudo --user root --login bash -c "sudo systemctl restart mariadb > /dev/null 2>&1"

      echo "Running MariaDB secure installation..."
      lxc exec "$DB_CONTAINER_NAME" -- sudo --user root --login bash -c "
        sudo mysql -e 'UPDATE mysql.user SET password = PASSWORD(\"$DB_ROOT_PASSWORD\") WHERE User = \"root\"';
        sudo mysql -e 'DELETE FROM mysql.user WHERE User = \"\"';
        sudo mysql -e 'DELETE FROM mysql.db WHERE Db = \"test\" OR Db = \"test_%\"';
        sudo mysql -e 'FLUSH PRIVILEGES';
      "
      echo "MariaDB installed and secured."
    else
      echo "MariaDB is already installed in the container."
    fi
  else
    echo "MySQL container $DB_CONTAINER_NAME already exists."
  fi

  # If MariaDB was just installed or it's the first time setting up, ensure root password is set.
  if ! lxc exec "$DB_CONTAINER_NAME" -- sudo --user root --login bash -c "sudo mysql -e 'SELECT User, Host FROM mysql.user WHERE User = \"root\";' | grep -q 'root'"; then
    echo "Setting root password..."
    lxc exec "$DB_CONTAINER_NAME" -- sudo --user root --login bash -c "echo 'root:$DB_ROOT_PASSWORD' | chpasswd"
    lxc exec "$DB_CONTAINER_NAME" -- sudo --user root --login bash -c "sudo mysql -e 'UPDATE mysql.user SET password = PASSWORD(\"$DB_ROOT_PASSWORD\") WHERE User = \"root\";'"
    echo "Root password set."
  else
    echo "Root password is already set."
  fi

  # Generate unique DB name and user for the WordPress instance
  DB_NAME=$(generate_unique_db_name "$WP_SITE_NAME")
  DB_USER=$(generate_unique_db_user "$WP_SITE_NAME")
  DB_PASSWORD=$(generate_random_password)

  echo "Generated Database Name: $DB_NAME"
  echo "Generated Database User: $DB_USER"
  echo "Generated Database Password: $DB_PASSWORD"

  # Create WordPress Database and User
  echo "Creating database and user..."
  lxc exec "$DB_CONTAINER_NAME" -- sudo --user root --login bash -c "sudo mysql -e \"CREATE DATABASE IF NOT EXISTS $DB_NAME;\""
  lxc exec "$DB_CONTAINER_NAME" -- sudo --user root --login bash -c "sudo mysql -e \"CREATE USER IF NOT EXISTS '$DB_USER'@'%' IDENTIFIED BY '$DB_PASSWORD';\""
  lxc exec "$DB_CONTAINER_NAME" -- sudo --user root --login bash -c "sudo mysql -e \"GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'%';\""
  lxc exec "$DB_CONTAINER_NAME" -- sudo --user root --login bash -c "sudo mysql -e \"FLUSH PRIVILEGES;\""

  # Save the credentials to a file
  echo "Saving credentials..."
  echo "$DB_NAME $DB_USER $DB_PASSWORD" > mysql_credentials.txt

  # Copy custom MariaDB configuration file if necessary
  echo "Copying custom MariaDB configuration..."
  lxc file push ./custom_mariadb.cnf "$DB_CONTAINER_NAME"/etc/mysql/mariadb.conf.d/50-server.cnf
  lxc exec "$DB_CONTAINER_NAME" -- sudo --user root --login bash -c "sudo systemctl restart mariadb > /dev/null 2>&1"

  echo "MySQL setup complete!"
}
