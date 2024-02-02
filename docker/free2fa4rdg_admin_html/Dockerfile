FROM nginx

WORKDIR /app

RUN apt-get update \
    && apt-get install -y ca-certificates apache2-utils \
    && update-ca-certificates

COPY start.sh .

COPY ./files/ /usr/share/nginx/html/

COPY ./nginx/nginx.conf /etc/nginx/nginx.conf

EXPOSE 443

RUN chmod +x start.sh

ENTRYPOINT ["start.sh"]
