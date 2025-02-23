#!/bin/bash

# ===========================
# WordPress Auto Deployment
# ===========================

# Export global variables
export SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export DOMAIN_GLOBAL=""
export WP_CONTAINER_GLOBAL=""
export DB_CONTAINER_NAME="db"
export DOMAIN=""
export WP_DOMAIN=""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m' # Reset color

# Validate domain format
validate_domain() {
    local domain="$1"
    if [[ ! "$domain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?)*\.[a-zA-Z]{2,}$ ]]; then
        echo "Invalid domain format. Please use format like example.com or sub.example.com"
        return 1
    fi
    return 0
}

# Sanitize container name
sanitize_container_name() {
    local name="$1"
    # Ensure name starts with a letter or number
    name=$(echo "$name" | sed 's/^[^a-zA-Z0-9]*//')
    # Replace invalid characters with hyphens and convert to lowercase
    name=$(echo "$name" | tr -cd 'a-zA-Z0-9-' | tr '[:upper:]' '[:lower:]')
    # Ensure name isn't empty after sanitization
    if [ -z "$name" ]; then
        name="wordpress-site"
    fi
    echo "$name"
}

# Fancy Header
echo -e "${CYAN}"
echo "========================================"
echo " 🚀 Auto LXD based WP by thxnlo 🚀"
echo "========================================"
echo -e "${RESET}"

# Prompt for user inputs
echo -e "${BOLD}${BLUE}Enter WordPress Configuration Details:${RESET}"

# Get and sanitize container name
read -p "Enter WordPress container name [wordpress-site]: " WP_CONTAINER_NAME
WP_CONTAINER_NAME=${WP_CONTAINER_NAME:-wordpress-site}
WP_CONTAINER_NAME=$(sanitize_container_name "$WP_CONTAINER_NAME")
export WP_CONTAINER_GLOBAL="$WP_CONTAINER_NAME"

# Get and validate domain
while true; do
    read -p "Enter the domain name for WordPress [example.com]: " DOMAIN
    DOMAIN=${DOMAIN:-example.com}
    if validate_domain "$DOMAIN"; then
        break
    fi
done

# Set global domain variables
export DOMAIN_GLOBAL="$DOMAIN"
export DOMAIN="$DOMAIN"
export WP_DOMAIN="$DOMAIN"

# Debug: check if domain is correctly set
echo "Debug: Domain variables set:"
echo "DOMAIN=$DOMAIN"
echo "WP_DOMAIN=$WP_DOMAIN"
echo "DOMAIN_GLOBAL=$DOMAIN_GLOBAL"
echo "WP_CONTAINER_GLOBAL=$WP_CONTAINER_GLOBAL"

# ===========================
# Function to Setup Cloudflare
# ===========================
setup_cloudflare() {
    local domain="$1"
    if [ -z "$domain" ]; then
        echo "Error: Domain not provided to setup_cloudflare"
        return 1
    fi

    read -p "Do you want to add the DNS record to Cloudflare? (yes/no): " ADD_CLOUDFLARE
    ADD_CLOUDFLARE=${ADD_CLOUDFLARE:-no}

    if [[ "$ADD_CLOUDFLARE" == "yes" ]]; then
        echo -e "${YELLOW}Checking for Cloudflare API and server details...${RESET}"

        # Load the .env file
        if [ -f "$SCRIPT_DIR/.env" ]; then
            source "$SCRIPT_DIR/.env"
        fi

        # Check if Cloudflare details exist, else ask for input
        check_cloudflare_details "$domain"
    fi
}

check_cloudflare_details() {
    local domain="$1"
    if [ -z "$domain" ]; then
        echo "Error: Domain not provided to check_cloudflare_details"
        return 1
    fi

    # Debug: check Cloudflare values
    echo "CLOUDFLARE_API: $CLOUDFLARE_API"
    echo "MY_SERVER_IP: $MY_SERVER_IP"
    echo "CF_ZONE_NAME: $CF_ZONE_NAME"

    if [[ -z "$CLOUDFLARE_API" || -z "$MY_SERVER_IP" || -z "$CF_ZONE_NAME" ]]; then
        echo "Cloudflare details not found or incomplete in .env."
        echo "Please enter them manually."

        if [ -z "$CLOUDFLARE_API" ]; then
            read -p "Enter your Cloudflare API key: " CLOUDFLARE_API
        fi

        if [ -z "$MY_SERVER_IP" ]; then
            read -p "Enter your server's IP address: " MY_SERVER_IP
        fi

        if [ -z "$CF_ZONE_NAME" ]; then
            read -p "Enter your Cloudflare zone name (e.g., thxnlo.com): " CF_ZONE_NAME
        fi

        # Save these details to the .env file for future use
        cat > "$SCRIPT_DIR/.env" << EOF
CLOUDFLARE_API=$CLOUDFLARE_API
MY_SERVER_IP=$MY_SERVER_IP
CF_ZONE_NAME=$CF_ZONE_NAME
EOF
    else
        echo -e "${YELLOW}Cloudflare details found in .env:"
        echo "API Key: $CLOUDFLARE_API"
        echo "Server IP: $MY_SERVER_IP"
        echo "Zone Name: $CF_ZONE_NAME"
        read -p "Are these details correct? (yes/no): " VERIFY_CLOUDFLARE
        VERIFY_CLOUDFLARE=${VERIFY_CLOUDFLARE:-no}

        if [[ "$VERIFY_CLOUDFLARE" == "no" ]]; then
            echo "Please re-enter the Cloudflare details."
            read -p "Enter your Cloudflare API key: " CLOUDFLARE_API
            read -p "Enter your server's IP address: " MY_SERVER_IP
            read -p "Enter your Cloudflare zone name (e.g., thxnlo.com): " CF_ZONE_NAME

            # Update .env with new details
            cat > "$SCRIPT_DIR/.env" << EOF
CLOUDFLARE_API=$CLOUDFLARE_API
MY_SERVER_IP=$MY_SERVER_IP
CF_ZONE_NAME=$CF_ZONE_NAME
EOF
        fi
    fi

    # Call Cloudflare function to add/update DNS record
    if [ -f "$SCRIPT_DIR/cloudflare.sh" ]; then
        source "$SCRIPT_DIR/cloudflare.sh"
        add_cloudflare_record "$domain" "$CLOUDFLARE_API" "$MY_SERVER_IP"
        echo -e "${GREEN}✅ Cloudflare DNS record setup complete!${RESET}"
    else
        echo "Error: cloudflare.sh not found in $SCRIPT_DIR"
        return 1
    fi
}

# ===========================
# WordPress Setup
# ===========================
setup_wordpress() {
    local domain="$1"
    
    # Export all required variables
    export WP_CONTAINER_NAME="$WP_CONTAINER_GLOBAL"
    export DOMAIN="$domain"
    export WP_DOMAIN="$domain"
    export DOMAIN_GLOBAL="$domain"
    
    # Debug output
    echo "Debug: Variables set in setup_wordpress:"
    echo "WP_CONTAINER_NAME=$WP_CONTAINER_NAME"
    echo "DOMAIN=$DOMAIN"
    echo "WP_DOMAIN=$WP_DOMAIN"
    echo "DOMAIN_GLOBAL=$DOMAIN_GLOBAL"
    

    # WordPress admin credentials
    read -p "Enter the WordPress admin username [admin]: " ADMIN_USER
    ADMIN_USER=${ADMIN_USER:-admin}

    while true; do
        read -s -p "Enter the WordPress admin password: " ADMIN_PASS
        echo
        if [[ ${#ADMIN_PASS} -ge 8 ]]; then
            break
        else
            echo "Password must be at least 8 characters long"
        fi
    done

    read -p "Enter the WordPress admin email [admin@example.com]: " ADMIN_EMAIL
    ADMIN_EMAIL=${ADMIN_EMAIL:-admin@example.com}

    # Extract WordPress site name from domain
    WP_SITE_NAME=$(echo "$domain" | cut -d'.' -f1)

    # Generate root password for database if not set
    if [ -z "$DB_ROOT_PASSWORD" ]; then
        DB_ROOT_PASSWORD=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 16)
        export DB_ROOT_PASSWORD
    fi

    # Source Modules After User Input
    local required_files=(
        "set_root_password_db.sh"
        "fix_permissions.sh"
        "create_mysql_container.sh"
        "create_wordpress_container.sh"
        "setup_proxy.sh"
        "setup_ssl.sh"
    )

    echo "Debug: About to source required files..."
    for file in "${required_files[@]}"; do
        echo "Debug: Attempting to source $file"
        if [ -f "$SCRIPT_DIR/$file" ]; then
            source "$SCRIPT_DIR/$file"
            echo "Debug: Successfully sourced $file"
        else
            echo "Error: Required file $file not found in $SCRIPT_DIR"
            return 1
        fi
    done

    echo "Debug: Domain before MySQL setup: $DOMAIN"
    # MySQL and WordPress setup
    echo -e "${YELLOW}📦 Setting up MySQL container...${RESET}"
    if ! create_mysql_container "$DB_CONTAINER_NAME" "$DB_ROOT_PASSWORD" "$WP_SITE_NAME" "$WP_CONTAINER_NAME"; then
        echo "Error: MySQL container setup failed"
        return 1
    fi
    echo -e "${GREEN}✅ MySQL setup complete!${RESET}"

    echo "Debug: Domain before WordPress setup: $DOMAIN"
    echo -e "${YELLOW}🌐 Setting up WordPress container...${RESET}"
    if ! create_wordpress_container "$WP_CONTAINER_NAME" "$domain" "$DB_CONTAINER_NAME" "$ADMIN_USER" "$ADMIN_PASS" "$ADMIN_EMAIL"; then
        echo "Error: WordPress container setup failed"
        return 1
    fi
    
    echo -e "${GREEN}✅ WordPress setup complete!${RESET}"

    echo "Debug: Before proxy setup - Variable check:"
    echo "DOMAIN=$DOMAIN"
    echo "WP_DOMAIN=$WP_DOMAIN"
    echo "WP_CONTAINER_NAME=$WP_CONTAINER_NAME"
    echo "WP_CONTAINER_GLOBAL=$WP_CONTAINER_GLOBAL"

    # Update the proxy setup section
    echo -e "${YELLOW}🔧 Configuring Proxy...${RESET}"
    echo "Debug: Before calling setup_proxy:"
    echo "WP_CONTAINER_NAME=$WP_CONTAINER_NAME"
    echo "WP_DOMAIN=$WP_DOMAIN"
    

    # Make sure these variables are available before calling setup_proxy
    echo "Debug: Final check before setup_proxy call:"
    echo "WP_CONTAINER_NAME=$WP_CONTAINER_NAME"
    echo "WP_DOMAIN=$WP_DOMAIN"
    echo "DOMAIN_GLOBAL=$DOMAIN_GLOBAL"



    # Call setup_proxy with explicit parameters
    if ! setup_proxy "proxy" "$WP_CONTAINER_NAME" "$WP_DOMAIN"; then
        echo "Error: Proxy setup failed"
        return 1
    fi
    echo -e "${GREEN}✅ Proxy setup complete!${RESET}"


    echo "Debug: Domain before SSL setup: $DOMAIN"
    echo -e "${YELLOW}🔒 Setting up SSL for $domain...${RESET}"
    if ! setup_ssl "$domain"; then
        echo "Error: SSL setup failed"
        return 1
    fi
    echo -e "${GREEN}✅ SSL setup complete!${RESET}"

    # Final Message
    echo -e "${BOLD}${CYAN}"
    echo "========================================"
    echo " 🎉 WordPress site is live at: https://$domain 🎉"
    echo "========================================"
    echo -e "${RESET}"
}

# ===========================
# Cleanup Function
# ===========================
cleanup() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        echo -e "${RED}An error occurred during execution. Exit code: $exit_code${RESET}"
    fi
    
    # Clear sensitive variables
    unset DB_ROOT_PASSWORD ADMIN_USER ADMIN_PASS ADMIN_EMAIL CLOUDFLARE_API
}

# Set trap for cleanup
trap cleanup EXIT

# ===========================
# Main Execution Logic
# ===========================

# Setup Cloudflare if needed
if ! setup_cloudflare "$DOMAIN_GLOBAL"; then
    echo "Error: Cloudflare setup failed"
    exit 1
fi

# Setup WordPress
if ! setup_wordpress "$DOMAIN_GLOBAL"; then
    echo "Error: WordPress setup failed"
    exit 1
fi

exit 0