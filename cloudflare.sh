#!/bin/bash

#file: cloudflare.sh

# Function to check if jq is installed
check_jq_installed() {
  if ! command -v jq &> /dev/null; then
    echo "jq is not installed. Installing..."
    sudo apt update
    sudo apt install -y jq || { echo "Failed to install jq. Exiting."; exit 1; }
  else
    echo "jq is already installed."
  fi
}

# Function to load the .env file and read variables
load_env_file() {
  if [ -f .env ]; then
    export $(grep -v '^#' .env | xargs)
  else
    echo ".env file not found. Exiting."
    exit 1
  fi
}

# Function to add or update DNS record in Cloudflare
add_cloudflare_record() {
  DOMAIN=$1
  CLOUDFLARE_API=$2
  MY_SERVER_IP=$3

  # Check if DOMAIN is set and not empty
  if [ -z "$DOMAIN" ]; then
    echo "Error: DOMAIN is not set. Exiting."
    exit 1
  fi

  # Check if jq is installed
  check_jq_installed

  # Load environment variables from .env
  load_env_file

  # Use CF_ZONE_NAME from .env to get the Cloudflare zone ID
  CF_ZONE_NAME=${CF_ZONE_NAME:-"thxnlo.com"}  # Default to 'thxnlo.com' if not set in .env

  # Check if the domain is a subdomain or root domain
  if [[ "$DOMAIN" =~ \..* ]]; then
    NAME=$DOMAIN
    TYPE="A"
  else
    NAME="$DOMAIN"
    TYPE="A"
  fi

  echo "Checking Cloudflare zone for the domain: $CF_ZONE_NAME"

  # Get Cloudflare Zone ID for the root domain
  ZONE_ID=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones" \
    -H "Authorization: Bearer $CLOUDFLARE_API" \
    -H "Content-Type: application/json" | jq -r ".result[] | select(.name==\"$CF_ZONE_NAME\") | .id")

  if [ -z "$ZONE_ID" ]; then
    echo "Zone for $CF_ZONE_NAME not found in Cloudflare. Exiting."
    exit 1
  fi

  # Check if the DNS record already exists
  DNS_RECORD_ID=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records" \
    -H "Authorization: Bearer $CLOUDFLARE_API" \
    -H "Content-Type: application/json" | jq -r ".result[] | select(.name==\"$NAME\") | .id")

  if [ -z "$DNS_RECORD_ID" ]; then
    echo "Adding DNS record for $NAME in Cloudflare..."
    # Add A record if it does not exist
    curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records" \
      -H "Authorization: Bearer $CLOUDFLARE_API" \
      -H "Content-Type: application/json" \
      --data '{"type":"A","name":"'"$NAME"'","content":"'"$MY_SERVER_IP"'","ttl":120,"proxied":true}' || { echo "Failed to add DNS record"; exit 1; }
  else
    echo "Updating existing DNS record for $NAME in Cloudflare..."
    # Update A record if it exists
    curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records/$DNS_RECORD_ID" \
      -H "Authorization: Bearer $CLOUDFLARE_API" \
      -H "Content-Type: application/json" \
      --data '{"type":"A","name":"'"$NAME"'","content":"'"$MY_SERVER_IP"'","ttl":120,"proxied":true}' || { echo "Failed to update DNS record"; exit 1; }
  fi
}
