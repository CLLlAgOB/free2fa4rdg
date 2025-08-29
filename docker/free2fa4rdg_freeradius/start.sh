#!/bin/bash

# start.sh
# Copyright (C) 2024 Voloskov Aleksandr Nikolaevich

# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.

#Applying customizations to the config.
CONFIG_FILE_RADIUS="/etc/freeradius/radiusd.conf"
CONFIG_FILE_CLIENT="/etc/freeradius/clients.conf"
CONFIG_FILE_REST="/etc/freeradius/mods-enabled/rest"

# Default values
CLIENT_SECRET=${RADIUS_CLIENT_SECRET:-"test123"}
REQUIRE_MESSAGE_AUTHENTICATOR=${REQUIRE_MESSAGE_AUTHENTICATOR:-"true"}
RADIUS_CLIENT_TIMEOUT=${RADIUS_CLIENT_TIMEOUT:-10}
RADIUS_START_SERVERS=${RADIUS_START_SERVERS:-5}
RADIUS_MAX_SERVERS=${RADIUS_MAX_SERVERS:-32}
RADIUS_MAX_SPARE_SERVERS=${RADIUS_MAX_SPARE_SERVERS:-10}
RADIUS_MIN_SPARE_SERVERS=${RADIUS_MIN_SPARE_SERVERS:-3}


key_file="/etc/freeradius/key"

# Check if the file exists
if [ ! -f "$key_file" ]; then
    # Generate 32 random characters
    random_key=$(head /dev/urandom | tr -dc 'a-zA-Z0-9' | head -c 32)

    # Write the key to a file
    echo "$random_key" | tee "$key_file" >/dev/null

    # Set read-only permissions for the root owner and the freerad group
    chown root:freerad "$key_file"
    chmod 440 "$key_file"
else
    # Read value from file
    random_key=$(cat "$key_file")
fi

# Updating configuration files
sed -i "s/secret = .*/secret = $CLIENT_SECRET/" "$CONFIG_FILE_CLIENT"
sed -i "s/require_message_authenticator = .*/require_message_authenticator = $REQUIRE_MESSAGE_AUTHENTICATOR/" "$CONFIG_FILE_CLIENT"
sed -i "s/limit_proxy_state = .*/limit_proxy_state = $REQUIRE_MESSAGE_AUTHENTICATOR/" "$CONFIG_FILE_CLIENT"
sed -i "/^rest {/,/^}/ s/connect_timeout = .*/connect_timeout = $((RADIUS_CLIENT_TIMEOUT + 3))/" "$CONFIG_FILE_REST"
sed -i "/^rest {/,/^}/ { /    authenticate {/,/    }/ s/timeout = .*/timeout = $((RADIUS_CLIENT_TIMEOUT + 3))/ }" "$CONFIG_FILE_REST"
sed -i "s/\"client_key\": \".*\"/\"client_key\": \"$random_key\"/" "$CONFIG_FILE_REST"
sed -i "s/start_servers = .*/start_servers = $RADIUS_START_SERVERS/" "$CONFIG_FILE_RADIUS"
sed -i "s/max_servers = .*/max_servers = $RADIUS_MAX_SERVERS/" "$CONFIG_FILE_RADIUS"
sed -i "s/max_spare_servers = .*/max_spare_servers = $RADIUS_MAX_SPARE_SERVERS/" "$CONFIG_FILE_RADIUS"
sed -i "s/min_spare_servers = .*/min_spare_servers = $RADIUS_MIN_SPARE_SERVERS/" "$CONFIG_FILE_RADIUS"
sed -i "s/destination = .*/destination = stdout/" "$CONFIG_FILE_RADIUS"

echo "Configuration updated."

# Setting access rights to configuration files
chmod 440 /etc/freeradius/clients.conf
chmod 440 /etc/freeradius/sites-enabled/default
chmod 440 /etc/freeradius/mods-enabled/rest
chmod 440 /etc/freeradius/mods-enabled/cache_2fa
chown root:freerad /etc/freeradius/clients.conf
chown root:freerad /etc/freeradius/sites-enabled/default
chown root:freerad /etc/freeradius/mods-enabled/rest
chown root:freerad /etc/freeradius/mods-available/cache_2fa
# Updating certificates
update-ca-certificates

echo "Waiting for free2fa api availability"
until curl -s --cacert /usr/local/share/ca-certificates/ca.crt -o /dev/null -w '%{http_code}' https://free2fa4rdg_api:5000/health | grep -q "200"; do
    sleep 5
done

echo "Install api key"
DATA='{"client_key":"'"$random_key"'", "user_name":"key"}'
curl -s -X POST https://free2fa4rdg_api:5000/authorize \
    -H "Content-Type: application/json" \
    -d "$DATA"

if [ "${FREE2FA_CACHE_ENABLED,,}" = "true" ]; then
    echo "[start] Enabling 2FA cache with TTL=${FREE2FA_CACHE_TTL:-32400}"
    # Turn on the module
    ln -sf /etc/freeradius/mods-available/cache_2fa /etc/freeradius/mods-enabled/cache_2fa

    # We correct the TTL in the module.
    sed -i "s/^\(\s*ttl\s*=\s*\).*$/\1${FREE2FA_CACHE_TTL:-32400}/" /etc/freeradius/mods-available/cache_2fa

    # Enable authorize/post-auth blocks for cache_2fa
    sed -i 's/#CACHE2FA_ENABLED//g' /etc/freeradius/sites-enabled/default
else
    echo "[start] Disabling 2FA cache"
    rm -f /etc/freeradius/mods-enabled/cache_2fa

    # Comment out the authorize/post-auth blocks for cache_2fa
    sed -i 's/^\(.*cache_2fa.*\)$/#CACHE2FA_DISABLED \1/' /etc/freeradius/sites-enabled/default
fi

# Starting the FreeRADIUS
su -s /bin/bash freerad -c "/usr/sbin/freeradius -f"
# For debug 
#su -s /bin/bash freerad -c "/usr/sbin/freeradius -X"