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

  # Create a new API token if needed
  echo "This script will create a new DNS record for $DOMAIN with IP $MY_SERVER_IP"
  echo "To do this, you need to create a proper API token with DNS edit permissions"
  
  # Give user option to continue or create a new token
  read -p "Do you already have a proper API token with DNS edit permissions? (yes/no): " HAS_TOKEN
  
  if [[ "$HAS_TOKEN" != "yes" ]]; then
    echo "Please follow these steps to create a new API token:"
    echo "1. Go to https://dash.cloudflare.com/profile/api-tokens"
    echo "2. Click 'Create Token'"
    echo "3. Select 'Edit zone DNS' template"
    echo "4. Under 'Zone Resources', select 'Include - Specific zone - $CF_ZONE_NAME'"
    echo "5. Click 'Continue to summary' and then 'Create Token'"
    echo "6. Copy the token and update your .env file with the new token"
    echo "   Add this line to your .env file: CLOUDFLARE_API=your_new_token_here"
    
    read -p "Have you created a new API token? (yes/no): " CREATED_TOKEN
    if [[ "$CREATED_TOKEN" != "yes" ]]; then
      echo "Cannot continue without proper API token. Exiting."
      exit 1
    fi
    
    read -p "Enter your new API token: " NEW_TOKEN
    if [ -n "$NEW_TOKEN" ]; then
      CLOUDFLARE_API=$NEW_TOKEN
      # Optionally update the .env file with the new token
      sed -i "s/CLOUDFLARE_API=.*/CLOUDFLARE_API=$NEW_TOKEN/" .env
      echo "Updated .env file with new API token"
    else
      echo "No token provided. Exiting."
      exit 1
    fi
  fi

  # Get Cloudflare Zone ID for the root domain
  echo "Checking Cloudflare zone for the domain: $CF_ZONE_NAME"
  
  # Try with API Token authentication
  echo "Using API Token authentication"
  local ZONE_RESPONSE=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones" \
    -H "Authorization: Bearer $CLOUDFLARE_API" \
    -H "Content-Type: application/json")
    
  if ! echo "$ZONE_RESPONSE" | jq -e '.success' &>/dev/null; then
    echo "API Token authentication failed. Error: $(echo "$ZONE_RESPONSE" | jq -r '.errors[0].message // "Unknown error"')"
    echo "Full response: $ZONE_RESPONSE"
    echo "Please verify your API token has the correct permissions."
    exit 1
  fi
  
  # Get Zone ID from the response
  local ZONE_ID=$(echo "$ZONE_RESPONSE" | jq -r ".result[] | select(.name==\"$CF_ZONE_NAME\") | .id")

  if [ -z "$ZONE_ID" ]; then
    echo "Zone for $CF_ZONE_NAME not found in Cloudflare. Exiting."
    exit 1
  fi

  echo "Found Zone ID: $ZONE_ID for $CF_ZONE_NAME"

  # Determine record name based on domain
  local RECORD_NAME
  if [ "$DOMAIN" = "$CF_ZONE_NAME" ]; then
    echo "Root domain detected."
    RECORD_NAME="@"  # Root domain for the API
    SEARCH_NAME="$CF_ZONE_NAME"  # But search using the full domain
  else
    # Handle full domain names vs. subdomains
    if [[ "$DOMAIN" == *".$CF_ZONE_NAME" ]]; then
      # Extract subdomain part
      RECORD_NAME="${DOMAIN%.$CF_ZONE_NAME}"
      SEARCH_NAME="$DOMAIN"
    else
      RECORD_NAME="$DOMAIN"
      SEARCH_NAME="$DOMAIN.$CF_ZONE_NAME"
    fi
  fi
  
  echo "Using record name: $RECORD_NAME for domain: $DOMAIN (search name: $SEARCH_NAME)"

  # Set auth headers for API Token
  local AUTH_HEADERS=(-H "Authorization: Bearer $CLOUDFLARE_API")

  # Check if the DNS record already exists
  echo "Checking for existing DNS records..."
  local DNS_LIST_URL="https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records?type=A&name=$SEARCH_NAME"
  echo "Querying: $DNS_LIST_URL"
  
  local DNS_RESPONSE=$(curl -s -X GET "$DNS_LIST_URL" \
    "${AUTH_HEADERS[@]}" \
    -H "Content-Type: application/json")
    
  if ! echo "$DNS_RESPONSE" | jq -e '.success' &>/dev/null; then
    echo "Error retrieving DNS records: $(echo "$DNS_RESPONSE" | jq -r '.errors[0].message // "Unknown error"')"
    echo "Full response: $DNS_RESPONSE"
    exit 1
  fi

  # Get existing record information
  local DNS_RECORD_COUNT=$(echo "$DNS_RESPONSE" | jq -r '.result | length')
  echo "Found $DNS_RECORD_COUNT existing record(s)"
  
  if [ "$DNS_RECORD_COUNT" -gt 0 ]; then
    local DNS_RECORD_ID=$(echo "$DNS_RESPONSE" | jq -r '.result[0].id')
    local CURRENT_IP=$(echo "$DNS_RESPONSE" | jq -r '.result[0].content')
    echo "Existing record: ID=$DNS_RECORD_ID, Current IP=$CURRENT_IP"
    
    # Check if the IP is different before updating
    if [ "$CURRENT_IP" = "$MY_SERVER_IP" ]; then
      echo "DNS record for $DOMAIN already points to $MY_SERVER_IP. No update needed."
    else
      echo "Updating DNS record from $CURRENT_IP to $MY_SERVER_IP..."
      
      # For API tokens we need to use PATCH to update only the content
      local UPDATE_RESPONSE=$(curl -s -X PATCH "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records/$DNS_RECORD_ID" \
        "${AUTH_HEADERS[@]}" \
        -H "Content-Type: application/json" \
        --data "{\"content\":\"$MY_SERVER_IP\"}")
        
      if echo "$UPDATE_RESPONSE" | jq -e '.success' &>/dev/null; then
        echo "Successfully updated DNS record for $DOMAIN"
      else
        echo "Failed to update DNS record: $(echo "$UPDATE_RESPONSE" | jq -r '.errors[0].message // "Unknown error"')"
        echo "Full response: $UPDATE_RESPONSE"
        
        # If the record exists but we can't update it, we can try to delete and recreate
        echo "Attempting to delete and recreate the record..."
        
        # Delete the existing record
        local DELETE_RESPONSE=$(curl -s -X DELETE "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records/$DNS_RECORD_ID" \
          "${AUTH_HEADERS[@]}" \
          -H "Content-Type: application/json")
          
        if echo "$DELETE_RESPONSE" | jq -e '.success' &>/dev/null; then
          echo "Successfully deleted existing DNS record."
          # Now create a new record (code below will handle this)
          DNS_RECORD_COUNT=0
        else
          echo "Failed to delete DNS record: $(echo "$DELETE_RESPONSE" | jq -r '.errors[0].message // "Unknown error"')"
          echo "Full response: $DELETE_RESPONSE"
          exit 1
        fi
      fi
    fi
  else
    echo "No existing DNS record found. Creating new record."
  fi

  # Create new record if needed
  if [ "$DNS_RECORD_COUNT" -eq 0 ]; then
    echo "Adding DNS record for $DOMAIN pointing to $MY_SERVER_IP..."
    
    local CREATE_RESPONSE=$(curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records" \
      "${AUTH_HEADERS[@]}" \
      -H "Content-Type: application/json" \
      --data "{\"type\":\"A\",\"name\":\"$RECORD_NAME\",\"content\":\"$MY_SERVER_IP\",\"ttl\":120,\"proxied\":$PROXIED}")
      
    if echo "$CREATE_RESPONSE" | jq -e '.success' &>/dev/null; then
      echo "Successfully added DNS record for $DOMAIN"
    else
      echo "Failed to add DNS record: $(echo "$CREATE_RESPONSE" | jq -r '.errors[0].message // "Unknown error"')"
      echo "Full response: $CREATE_RESPONSE"
      exit 1
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
  if [ -z "$MY_SERVER_IP" ]; then
    MY_SERVER_IP=$(get_public_ip)
    echo "Using current public IP: $MY_SERVER_IP"
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
  MY_SERVER_IP="${3:-$MY_SERVER_IP}"
  
  # Add/update the DNS record
  add_cloudflare_record "$DOMAIN" "$CLOUDFLARE_API" "$MY_SERVER_IP" "$PROXIED"
}

# Execute main function with all command line arguments
main "$@"