# lxdautomated
 
# 🚀 LXD WordPress Automation - How it works

This project automates the deployment of **WordPress** using **LXD containers**. The automation is handled by `main.sh`, which:

- Creates and configures **LXD containers** for the database, WordPress, and reverse proxy.
- Installs and sets up **MariaDB**, **Nginx**, **PHP**, and **WordPress**.
- Configures **reverse proxy** with **SSL (Certbot)** for secure HTTPS access.

---

## 📝 Overview of `main.sh`

### **📌 What Does It Do?**

When you execute `main.sh`, it performs these steps:

1. **Checks for an existing LXD environment.**
2. **Creates a dedicated database container (`db-container`).**
3. **Creates a separate WordPress container (`wordpress-container-{sitename}`).**
4. **Creates a reverse proxy container (`proxy-container`).**
5. **Sets up SSL certificates with Certbot.**
6. **Ensures all services are running correctly.**

---

## 🔥 Step-by-Step Execution of `main.sh`

### **1️⃣ LXD Setup & Environment Check**

Before proceeding, `main.sh` ensures that LXD is installed and initialized.

```bash
echo "Checking if LXD is installed..."
if ! command -v lxc &> /dev/null; then
    echo "LXD not found. Installing..."
    sudo apt update && sudo apt install -y lxd
    sudo lxd init --auto
fi
```

**🔹 What’s Happening?**

- It checks if **LXD** is installed.
- If LXD is missing, it installs and initializes it automatically.

---

### **2️⃣ Creating the Database (DB) Container**

The script creates **a single MariaDB container** (`db-container`) for all WordPress sites.

```bash
echo "Creating Database Container..."
lxc launch ubuntu:22.04 db-container
sleep 10  # Wait for the container to initialize
lxc exec db-container -- sudo apt update
lxc exec db-container -- sudo apt install -y mariadb-server
lxc exec db-container -- sudo systemctl enable --now mariadb
```

**🔹 What’s Happening?**

- It launches a new LXD container named `db-container`.
- Installs **MariaDB** as the database server.
- Enables MariaDB to start automatically on reboot.

---

### **3️⃣ Securing the Database & Creating a WordPress DB**

```bash
lxc exec db-container -- sudo mysql -e "
ALTER USER 'root'@'localhost' IDENTIFIED WITH caching_sha2_password BY 'password';
FLUSH PRIVILEGES;"
lxc exec db-container -- sudo mysql_secure_installation
lxc exec db-container -- sudo mariadb -e "
CREATE DATABASE wordpress_db CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_520_ci;
CREATE USER 'wp_user'@'%' IDENTIFIED BY 'password';
GRANT ALL PRIVILEGES ON wordpress_db.* TO 'wp_user'@'%';
FLUSH PRIVILEGES;"
```

**🔹 What’s Happening?**

- Secures **MySQL root user** authentication.
- Runs **mysql_secure_installation** to remove weak defaults.
- Creates **a new database and user** (`wp_user`) for WordPress.
- Replaces default MariaDB configuration with `custom_mariadb.cnf`.

#### **MariaDB Custom Configuration (`custom_mariadb.cnf`)**

The script replaces the default MariaDB config file with our custom version:

```bash
lxc file push custom_mariadb.cnf db-container/etc/mysql/mariadb.conf.d/50-server.cnf
lxc exec db-container -- sudo systemctl restart mariadb
```

[View `custom_mariadb.cnf`](https://github.com/thxnlo/lxdautomated/blob/main/custom_mariadb.cnf)

---

### **4️⃣ Creating the WordPress Container**

Each WordPress site gets a separate container named `wordpress-container-{sitename}`.

```bash
echo "Creating WordPress Container..."
lxc launch ubuntu:22.04 wordpress-container-example
sleep 10
lxc exec wordpress-container-example -- sudo apt update
lxc exec wordpress-container-example -- sudo apt install -y nginx php8.3-fpm php8.3-mysql wp-cli
```

**🔹 What’s Happening?**

- It creates a new LXD container (`wordpress-container-example`).
- Installs **Nginx**, **PHP**, and **WP-CLI** for managing WordPress.

---

### **5️⃣ Configuring PHP & WordPress Setup**

```bash
lxc exec wordpress-container-example -- sudo mkdir -p /var/www/html
lxc exec wordpress-container-example -- sudo chown -R www-data:www-data /var/www/html
lxc exec wordpress-container-example -- sudo -u www-data wp core download --path=/var/www/html
lxc exec wordpress-container-example -- sudo -u www-data wp core config --path=/var/www/html \
    --dbname=wordpress_db --dbuser=wp_user --dbpass='password' --dbhost=db-container.lxd
lxc exec wordpress-container-example -- sudo -u www-data wp core install --path=/var/www/html \
    --url="https://example.com" --title="Example Site" --admin_user="admin" --admin_password="password" --admin_email="admin@example.com"
```

**🔹 What’s Happening?**

- It **downloads WordPress** inside `/var/www/html`.
- Configures WordPress with **DB credentials**.
- Installs WordPress with **admin credentials**.

---

### **6️⃣ Reverse Proxy Configuration with Nginx**

The script uses an **Nginx template file (`nginx_proxy_config.template`)** to configure the proxy container dynamically.

#### **nginx_proxy_config.template**

```nginx
server {
    listen 80 proxy_protocol;
    listen [::]:80 proxy_protocol;

    server_name ${WP_DOMAIN};

    location / {
        include /etc/nginx/proxy_params;
        proxy_pass http://${WP_CONTAINER_NAME}.lxd;
    }

    real_ip_header proxy_protocol;
    set_real_ip_from 127.0.0.1;
}
```

**🔹 What’s Happening?**

- The script replaces `${WP_DOMAIN}` with the actual domain name.
- It replaces `${WP_CONTAINER_NAME}` with the WordPress LXD container name.
- The updated config is stored in `/etc/nginx/sites-available/{domain}` and linked to `/etc/nginx/sites-enabled/`.

To enable SSL, Certbot is used:

```bash
sudo certbot --nginx -d example.com
sudo certbot renew --dry-run
```

**🔹 What’s Happening?**

- Certbot configures HTTPS with SSL certificates.
- The proxy configuration is updated to handle SSL correctly.

---

## 🔍 Final Execution

To deploy everything, simply run:

```bash
sudo bash main.sh
```

This will:  
💚 **Create LXD Containers** (DB, WordPress, Proxy)  
💚 **Install WordPress & Configure DB**  
💚 **Setup Nginx & SSL**  
💚 **Make the WordPress site live!** 🎉

---

## 🔥 Summary

- `main.sh` **automates WordPress deployment** inside LXD containers.
- **Database, WordPress, and Proxy Containers** are created dynamically.
- **Nginx reverse proxy** routes traffic correctly.
- **SSL Certificates** are issued automatically.

This project ensures **scalability, security, and automation** for self-hosted WordPress sites! 🚀