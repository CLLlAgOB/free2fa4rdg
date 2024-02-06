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
chown root:freerad /etc/freeradius/clients.conf
chown root:freerad /etc/freeradius/sites-enabled/default
chown root:freerad /etc/freeradius/mods-enabled/rest
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

# Starting the FreeRADIUS
su -s /bin/bash freerad -c "/usr/sbin/freeradius -f"
# For debug 
#su -s /bin/bash freerad -c "/usr/sbin/freeradius -X"