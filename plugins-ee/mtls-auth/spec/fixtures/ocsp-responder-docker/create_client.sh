#!/bin/bash
#First generate the key for the client

openssl genrsa \
      -out /root/ca/intermediate/private/$1.key.pem 2048 &>/dev/null
chmod 400 /root/ca/intermediate/private/$1.key.pem

#Then create the certificate signing request
openssl req -config /root/ca/intermediate/openssl.cnf \
      -key /root/ca/intermediate/private/$1.key.pem \
      -new -sha256 -out /root/ca/intermediate/csr/$1.csr.pem \
      -subj "/C=US/ST=CA/L=SF/O=kong/OU=FTT/CN=$1@konghq.com" &>/dev/null

#Now sign it with the intermediate CA
echo -e "y\ny\n" | openssl ca -config /root/ca/intermediate/openssl.cnf \
      -extensions $2 -days 365 -notext -md sha256 \
      -in /root/ca/intermediate/csr/$1.csr.pem \
      -out /root/ca/intermediate/certs/$1.cert.pem &>/dev/null

chmod 444 /root/ca/intermediate/certs/$1.cert.pem

cat /root/ca/intermediate/certs/$1.cert.pem
cat /root/ca/intermediate/certs/intermediate.cert.pem