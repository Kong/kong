#!/bin/sh
#Add client to the CRL (certificate revocation list)
openssl ca -config /root/ca/intermediate/openssl.cnf \
      -revoke /root/ca/intermediate/certs/$1.cert.pem

# generate CRL file
openssl ca -config /root/ca/intermediate/openssl.cnf \
      -gencrl -out /root/ca/intermediate/crl/intermediate.crl.pem

# copy to the directory of crl server
cp /root/ca/intermediate/crl/intermediate.crl.pem /var/www/kong.crl
