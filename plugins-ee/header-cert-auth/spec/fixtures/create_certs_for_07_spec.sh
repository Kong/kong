#!/bin/bash

# ca1 -> client1
# ca2 -> client2
#
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out ca1.key
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out ca2.key 

openssl req -x509 -new -key ca1.key -out ca1.crt -days 3650 \
    -subj "/C=US/ST=CA/L=SF/O=kong/OU=FTT/CN=kongroot1/EMAIL=kongroot1@konghq.com"
openssl req -x509 -new -key ca2.key -out ca2.crt -days 3650 \
    -subj "/C=US/ST=CA/L=SF/O=kong/OU=FTT/CN=kongroot2/EMAIL=kongroot2@konghq.com"

openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out client1.key 
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out client2.key 

openssl req -new -key client1.key -out client1.csr \
    -subj "/C=US/ST=CA/L=SF/O=kong/OU=FTT/CN=kongclient/EMAIL=kongclient1@konghq.com"

openssl req -new -key client2.key -out client2.csr \
    -subj "/C=US/ST=CA/L=SF/O=kong/OU=FTT/CN=kongclient/EMAIL=kongclient2@konghq.com"

openssl x509 -req -in client1.csr -CA ca1.crt -CAkey ca1.key -CAcreateserial -out client1.crt -days 3650
openssl x509 -req -in client2.csr -CA ca2.crt -CAkey ca2.key -CAcreateserial -out client2.crt -days 3650

rm ca1.key ca1.srl ca2.key ca2.srl client1.csr client2.csr
