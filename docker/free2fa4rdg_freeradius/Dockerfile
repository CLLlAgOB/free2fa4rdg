# syntax=docker/dockerfile:1.7
FROM freeradius/freeradius-server:latest

ENV DEBIAN_FRONTEND=noninteractive

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends curl ca-certificates; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*

COPY --chmod=0755 start.sh /start.sh

COPY default /etc/freeradius/sites-available/default
COPY clients.conf /etc/freeradius/clients.conf
COPY rest /etc/freeradius/mods-enabled/rest
COPY cache_2fa /etc/freeradius/mods-available/cache_2fa
COPY linelog-cache2fa /etc/freeradius/mods-available/linelog-cache2fa

EXPOSE 1812/udp 1813/udp

HEALTHCHECK --interval=30s --timeout=5s --retries=5 CMD \
  /usr/sbin/freeradius -XC >/dev/null 2>&1 || exit 1

ENTRYPOINT ["/start.sh"]
