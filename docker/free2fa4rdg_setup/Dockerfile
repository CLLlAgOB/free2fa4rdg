FROM alpine:latest

RUN apk --no-cache add openssl curl

COPY generate-certs.sh /usr/local/bin/generate-certs.sh

WORKDIR /certs

ENTRYPOINT ["generate-certs.sh"]
