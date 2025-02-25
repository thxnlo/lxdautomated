#!/bin/bash

#file: cloudflare.sh

# Function to check if jq is installed
check_jq_installed() {
  if ! command -v jq &> /dev/null; then
    echo "jq is not installed. Installing..."
    if command -v apt &> /dev/null; then
      sudo apt update
      sudo apt install -y jq || { echo "Failed to install jq. Exiting."; exit 1; }
    elif command -v yum &> /dev/null; then
      sudo yum install -y jq || { echo "Failed to install jq. Exiting."; exit 1; }
    elif command -v brew &> /dev/null; then
      brew install jq || { echo "Failed to install jq. Exiting."; exit 1; }
    else
      echo "Could not determine package manager. Please install jq manually."
      exit 1
    fi
  else
    echo "jq is already installed."
  fi
}

# Function to load the .env file and read variables
load_env_file() {
  if [ -f .env ]; then
    export $(grep -v '^#' .env | xargs)
    # Validate required environment variables
    if [ -z "$CLOUDFLARE_API" ]; then
      echo "CLOUDFLARE_API is not set in .env file. Exiting."
      exit 1
    fi
    if [ -z "$CF_ZONE_NAME" ]; then
      echo "CF_ZONE_NAME is not set in .env file. Using default 'thxnlo.com'."
      export CF_ZONE_NAME="thxnlo.com"
    fi
  else
    echo ".env file not found. Exiting."
    exit 1
  fi
}

# Function to get current public IP
get_public_ip() {
  # Try multiple services in case one fails
  IP=$(curl -s https://ipinfo.io/ip || 
       curl -s https://api.ipify.org || 
       curl -s https://icanhazip.com)
  
  if [[ ! $IP =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Failed to retrieve valid public IP. Exiting."
    exit 1
  fi
  
  echo "$IP"
}

# Function to add or update DNS record in Cloudflare
add_cloudflare_record() {
  local DOMAIN=$1
  local CLOUDFLARE_API=$2
  local MY_SERVER_IP=$3
  local PROXIED=${4:-true}  # Default to proxied if not specified

  # Check if DOMAIN is set and not empty
  if [ -z "$DOMAIN" ]; then
    echo "Error: DOMAIN is not set. Exiting."
    exit 1
  fi

  # Get Cloudflare Zone ID for the root domain
  echo "Checking Cloudflare zone for the domain: $CF_ZONE_NAME"
  local ZONE_RESPONSE=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones" \
    -H "Authorization: Bearer $CLOUDFLARE_API" \
    -H "Content-Type: application/json")
    
  if ! echo "$ZONE_RESPONSE" | jq -e '.success' &>/dev/null; then
    # Try with API Token authentication
    ZONE_RESPONSE=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones" \
      -H "Authorization: Bearer $CLOUDFLARE_API" \
      -H "Content-Type: application/json")
    
    # If that fails, try with API Key authentication
    if ! echo "$ZONE_RESPONSE" | jq -e '.success' &>/dev/null; then
      ZONE_RESPONSE=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones" \
        -H "X-Auth-Email: $CF_EMAIL" \
        -H "X-Auth-Key: $CLOUDFLARE_API" \
        -H "Content-Type: application/json")
        
      # If this also fails, exit with error
      if ! echo "$ZONE_RESPONSE" | jq -e '.success' &>/dev/null; then
        echo "Error retrieving zones: $(echo "$ZONE_RESPONSE" | jq -r '.errors[0].message // "Unknown error"')"
        echo "Please check your Cloudflare API credentials."
        exit 1
      else
        # Set the auth method to API Key
        AUTH_METHOD="API_KEY"
      fi
    else
      # Set the auth method to API Token
      AUTH_METHOD="API_TOKEN"
    fi
  else
    # Default auth method is Bearer Token
    AUTH_METHOD="BEARER"
  fi
  
  local ZONE_ID=$(echo "$ZONE_RESPONSE" | jq -r ".result[] | select(.name==\"$CF_ZONE_NAME\") | .id")

  if [ -z "$ZONE_ID" ]; then
    echo "Zone for $CF_ZONE_NAME not found in Cloudflare. Exiting."
    exit 1
  fi

  # Determine if the domain is a subdomain or root domain
  if [ "$DOMAIN" = "$CF_ZONE_NAME" ]; then
    NAME="@"  # Root domain
  else
    # Handle full domain names vs. subdomains
    if [[ "$DOMAIN" == *"$CF_ZONE_NAME"* ]]; then
      # Extract subdomain part
      NAME="${DOMAIN%.$CF_ZONE_NAME}"
    else
      NAME="$DOMAIN"
    fi
  fi
  
  echo "Using record name: $NAME for domain: $DOMAIN"

  # Set the appropriate headers based on authentication method
  if [ "$AUTH_METHOD" = "API_KEY" ]; then
    AUTH_HEADERS=(-H "X-Auth-Email: $CF_EMAIL" -H "X-Auth-Key: $CLOUDFLARE_API")
    echo "Using API Key authentication method"
  elif [ "$AUTH_METHOD" = "API_TOKEN" ]; then
    AUTH_HEADERS=(-H "Authorization: Bearer $CLOUDFLARE_API")
    echo "Using API Token authentication method"
  else
    AUTH_HEADERS=(-H "Authorization: Bearer $CLOUDFLARE_API")
    echo "Using Bearer Token authentication method"
  fi

  # Check if the DNS record already exists
  local DNS_RESPONSE=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records?type=A&name=$DOMAIN" \
    "${AUTH_HEADERS[@]}" \
    -H "Content-Type: application/json")
    
  if ! echo "$DNS_RESPONSE" | jq -e '.success' &>/dev/null; then
    echo "Error retrieving DNS records: $(echo "$DNS_RESPONSE" | jq -r '.errors[0].message // "Unknown error"')"
    exit 1
  fi
  
  local DNS_RECORD_ID=$(echo "$DNS_RESPONSE" | jq -r '.result[0].id')
  local CURRENT_IP=$(echo "$DNS_RESPONSE" | jq -r '.result[0].content')

  # Create or update the record
  if [ -z "$DNS_RECORD_ID" ]; then
    echo "Adding DNS record for $DOMAIN pointing to $MY_SERVER_IP..."
    
    local CREATE_RESPONSE=$(curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records" \
      "${AUTH_HEADERS[@]}" \
      -H "Content-Type: application/json" \
      --data "{\"type\":\"A\",\"name\":\"$NAME\",\"content\":\"$MY_SERVER_IP\",\"ttl\":120,\"proxied\":$PROXIED}")
      
    if echo "$CREATE_RESPONSE" | jq -e '.success' &>/dev/null; then
      echo "Successfully added DNS record for $DOMAIN"
    else
      echo "Failed to add DNS record: $(echo "$CREATE_RESPONSE" | jq -r '.errors[0].message // "Unknown error"')"
      exit 1
    fi
  else
    # Check if the IP is different before updating
    if [ "$CURRENT_IP" = "$MY_SERVER_IP" ]; then
      echo "DNS record for $DOMAIN already points to $MY_SERVER_IP. No update needed."
    else
      echo "Updating existing DNS record for $DOMAIN from $CURRENT_IP to $MY_SERVER_IP..."
      
      local UPDATE_RESPONSE=$(curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records/$DNS_RECORD_ID" \
        "${AUTH_HEADERS[@]}" \
        -H "Content-Type: application/json" \
        --data "{\"type\":\"A\",\"name\":\"$NAME\",\"content\":\"$MY_SERVER_IP\",\"ttl\":120,\"proxied\":$PROXIED}")
        
      if echo "$UPDATE_RESPONSE" | jq -e '.success' &>/dev/null; then
        echo "Successfully updated DNS record for $DOMAIN"
      else
        echo "Failed to update DNS record: $(echo "$UPDATE_RESPONSE" | jq -r '.errors[0].message // "Unknown error"')"
        exit 1
      fi
    fi
  fi
}

# Main function
main() {
  # Check if jq is installed
  check_jq_installed
  
  # Load environment variables from .env
  load_env_file
  
  # Get the server's current public IP if not provided
  if [ -z "$SERVER_IP" ]; then
    SERVER_IP=$(get_public_ip)
    echo "Using current public IP: $SERVER_IP"
  fi
  
  # Check command line arguments
  if [ $# -eq 0 ]; then
    echo "Usage: $0 <domain> [proxied] [ip]"
    echo "  domain: Domain or subdomain to update (e.g., example.com or sub.example.com)"
    echo "  proxied: (Optional) 'true' or 'false' to enable/disable Cloudflare proxying (default: true)"
    echo "  ip: (Optional) IP address to set (default: auto-detected public IP)"
    exit 1
  fi
  
  DOMAIN="$1"
  PROXIED="${2:-true}"
  SERVER_IP="${3:-$SERVER_IP}"
  
  # Add/update the DNS record
  add_cloudflare_record "$DOMAIN" "$CLOUDFLARE_API" "$SERVER_IP" "$PROXIED"
}

# Execute main function with all command line arguments
main "$@"