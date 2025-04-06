#!/bin/bash

# install.ssh
# Copyright (C) 2024 Voloskov Aleksandr Nikolaevich

# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.

# Check for root privileges
if [ "$(id -u)" != "0" ]; then
    echo "This script must be run as root. Please run again with sudo or as root."
    exit 1
fi

# Function to install Docker
install_docker() {
    echo "Installing Docker..."
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh
    systemctl enable docker
    systemctl start docker
}

# Function to generate a random key
generate_random_key() {
    tr -dc 'a-zA-Z0-9' < /dev/urandom | fold -w 32 | head -n 1
}

# Function to create a .env file
create_env_file() {
    cat > .env << EOF
CA_EXPIRY_DAYS=${1:-365}
FREE2FA_TELEGRAM_BOT_TOKEN=${2:-yourkey}
FREE2FA_TELEGRAM_BOT_LANGUAGE=${3:-ru}
FREE2FA_AUTO_REG_ENABLED=${4:-true}
FREE2FA_BYPASS_ENABLED=${5:-true}
RADIUS_CLIENT_SECRET=${6:-secret123}
FREE2FA_TIMEOUT=${7:-10}
RADIUS_START_SERVERS=${8:-5}
RADIUS_MAX_SERVERS=${9:-20}
RADIUS_MAX_SPARE_SERVERS=${10:-10}
RADIUS_MIN_SPARE_SERVERS=${11:-5}
ADMIN_SECRET_KEY=${12:-$(generate_random_key)}
RESET_PASSWORD=${13:-false}
ALLOW_API_FAILURE_PASS=${14:-true}
RESET_PASSWORD=${15:-false}
ALLOW_API_FAILURE_PASS=${16:-false}
ADDITIONAL_DNS_NAME_FOR_ADMIN_HTML=${17:-free2fa4rdg}
REQUIRE_MESSAGE_AUTHENTICATOR=${18:-true}
EOF
}

# Check and install Docker and Docker Compose
echo "Checking for Docker and Docker Compose..."
if ! [ -x "$(command -v docker)" ]; then
    echo "Docker is not installed. Install it? (y/n)"
    read install_docker_choice
    if [ "$install_docker_choice" = "y" ]; then
        install_docker
    fi
fi

# Input parameters for the .env file
echo "Please enter the following parameters for the .env file. Press Enter to use the default value."
echo "CA_EXPIRY_DAYS: Validity period of the self-signed certificate (default 365 days)"
read -p "Enter CA_EXPIRY_DAYS (default 365): " CA_EXPIRY_DAYS
echo "---------------------------------------------------------------------------------------------------------------"
echo "FREE2FA_TELEGRAM_BOT_TOKEN: Your Telegram bot key"
read -p "Enter FREE2FA_TELEGRAM_BOT_TOKEN (default your-key): " FREE2FA_TELEGRAM_BOT_TOKEN
echo "---------------------------------------------------------------------------------------------------------------"
echo "FREE2FA_TELEGRAM_BOT_LANGUAGE: Language model, ru or en (default ru)"
read -p "Enter FREE2FA_TELEGRAM_BOT_LANGUAGE (default ru): " FREE2FA_TELEGRAM_BOT_LANGUAGE
echo "---------------------------------------------------------------------------------------------------------------"
echo "FREE2FA_AUTO_REG_ENABLED: Automatic registration of new users with Telegram ID 0 (default true)"
read -p "Enter FREE2FA_AUTO_REG_ENABLED (default true): " FREE2FA_AUTO_REG_ENABLED
echo "---------------------------------------------------------------------------------------------------------------"
echo "FREE2FA_BYPASS_ENABLED: Bypass all users with Telegram ID 0 without a request (default true)"
read -p "Enter FREE2FA_BYPASS_ENABLED (default true): " FREE2FA_BYPASS_ENABLED
echo "---------------------------------------------------------------------------------------------------------------"
echo "RADIUS_CLIENT_SECRET: Secret phrase for RADIUS (default secret123)"
read -p "Enter RADIUS_CLIENT_SECRET (default secret123): " RADIUS_CLIENT_SECRET
echo "---------------------------------------------------------------------------------------------------------------"
echo "FREE2FA_TIMEOUT: Waiting time for confirmation or rejection of login in the range of 10 to 20 seconds (default 20 seconds)"
read -p "Enter FREE2FA_TIMEOUT (default 20): " FREE2FA_TIMEOUT
echo "---------------------------------------------------------------------------------------------------------------"
echo "RADIUS_START_SERVERS: Number of initial RADIUS server processes (default 5)"
read -p "Enter RADIUS_START_SERVERS (default 5): " RADIUS_START_SERVERS
echo "---------------------------------------------------------------------------------------------------------------"
echo "RADIUS_MAX_SERVERS: Maximum number of RADIUS server processes (default 20)"
read -p "Enter RADIUS_MAX_SERVERS (default 20): " RADIUS_MAX_SERVERS
echo "---------------------------------------------------------------------------------------------------------------"
echo "RADIUS_MAX_SPARE_SERVERS: Maximum number of backup RADIUS server processes (default 10)"
read -p "Enter RADIUS_MAX_SPARE_SERVERS (default 10): " RADIUS_MAX_SPARE_SERVERS
echo "---------------------------------------------------------------------------------------------------------------"
echo "RADIUS_MIN_SPARE_SERVERS: Minimum number of backup RADIUS server processes (default 5)"
read -p "Enter RADIUS_MIN_SPARE_SERVERS (default 5): " RADIUS_MIN_SPARE_SERVERS
echo "---------------------------------------------------------------------------------------------------------------"
echo "ADMIN_SECRET_KEY: Administrator key (auto-generated if left empty)"
read -p "Enter ADMIN_SECRET_KEY (auto-generated if empty):" ADMIN_SECRET_KEY
echo "---------------------------------------------------------------------------------------------------------------"
echo "RESET_PASSWORD: Enables resetting the forgotten administrator password"
read -p "Enter RESET_PASSWORD (default false): " RESET_PASSWORD
echo "---------------------------------------------------------------------------------------------------------------"
echo "ALLOW_API_FAILURE_PASS: Skips the second factor if api.telegram.ru is not available (default false)"
read -p "Enter ALLOW_API_FAILURE_PASS (default false):" ALLOW_API_FAILURE_PASS
echo "---------------------------------------------------------------------------------------------------------------"
echo "ADDITIONAL_DNS_NAME_FOR_ADMIN_HTML: DNS name that will be added to the self-signed certificate."
read -p "Enter ADDITIONAL_DNS_NAME_FOR_ADMIN_HTML (default free2fa4rdg): " ADDITIONAL_DNS_NAME_FOR_ADMIN_HTML
echo "---------------------------------------------------------------------------------------------------------------"
echo "REQUIRE_MESSAGE_AUTHENTICATOR: Require mandatory Message-Authenticator attribute in RADIUS messages (default true)"
read -p "Enter REQUIRE_MESSAGE_AUTHENTICATOR (default true): " REQUIRE_MESSAGE_AUTHENTICATOR


create_env_file "$CA_EXPIRY_DAYS" "$FREE2FA_TELEGRAM_BOT_TOKEN" "$FREE2FA_TELEGRAM_BOT_LANGUAGE" "$FREE2FA_AUTO_REG_ENABLED" "$FREE2FA_BYPASS_ENABLED" "$RADIUS_CLIENT_SECRET" "$FREE2FA_TIMEOUT" "$RADIUS_START_SERVERS" "$RADIUS_MAX_SERVERS" "$RADIUS_MAX_SPARE_SERVERS" "$RADIUS_MIN_SPARE_SERVERS" "$ADMIN_SECRET_KEY" "$RESET_PASSWORD" "$ALLOW_API_FAILURE_PASS" "$RESET_PASSWORD" "$ALLOW_API_FAILURE_PASS" "$ADDITIONAL_DNS_NAME_FOR_ADMIN_HTML" "$REQUIRE_MESSAGE_AUTHENTICATOR"

# Download docker-compose.yml
curl -L "https://raw.githubusercontent.com/CLLlAgOB/free2fa4rdg/main/docker-compose/docker-compose.yml" -o docker-compose.yml
echo "docker-compose.yml downloaded."

# Prompt to start the build
echo "To start enter"
echo "docker compose up -d"
echo "To view logs enter"
echo "docker compose logs -f"
