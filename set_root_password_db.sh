#!/bin/bash

#file: set_root_password_db.sh

# Function to set root password in the database container
set_root_password_db() {
  container=$1
  password=$2
  echo "Setting root password for MySQL in container $container..."
  
  # Set the root password for MySQL container (as root user)
  lxc exec "$container" -- sudo --user root --login bash -c "echo 'root:$password' | chpasswd"
}
