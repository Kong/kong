#!/bin/sh
#Add client to the CRL (certificate revocation list)
openssl ca -config /root/ca/intermediate/openssl.cnf \
      -revoke /root/ca/intermediate/certs/$1.cert.pem
# generate CRL file
openssl ca -config /root/ca/intermediate/openssl.cnf \
      -gencrl

# openssl crl -inform PEM -in crl.pem -outform DER -out kong.crl