FROM freeradius/freeradius-server:3.2.3

RUN apt-get update \
    && apt-get install -y --no-install-recommends curl \
    # Cleaning up cache and temporary files to reduce image size
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* 

COPY start.sh /start.sh
COPY default /etc/freeradius/sites-available/default
COPY clients.conf /etc/freeradius/clients.conf
COPY rest /etc/freeradius/mods-enabled/rest

RUN chmod +x /start.sh

EXPOSE 1812/udp

ENTRYPOINT ["/start.sh"]
