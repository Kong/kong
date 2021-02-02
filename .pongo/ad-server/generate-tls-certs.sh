#!/bin/bash
set -e

mkdir -p ssl/
cd ssl/

openssl req -newkey rsa:2048 -keyout myKey.pem -nodes -x509 -days 999999 -out myCert.pem \
    -subj '/CN=localhost.ldap.mashape.com' -extensions EXT -config <( \
    printf "[dn]\nCN=localhost.ldap.mashape.com\n[req]\ndistinguished_name = dn\n[EXT]\nsubjectAltName=DNS:localhost.ldap.mashape.com,DNS:ad-server.ldap.mashape.com,DNS:ad-server\nkeyUsage=digitalSignature\nextendedKeyUsage=serverAuth")

chmod 600 myKey.pem
chmod 600 myCert.pem