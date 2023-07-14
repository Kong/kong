#!/bin/bash -x
#This entrypoint is responsible for leaving the OSCP running to accept requests

# Issue a valid certificate
/create_client valid usr_cert
/get_cert valid > /data/valid.pem
/get_key valid > /data/valid.pem.key

# Issue another certificate to defeat caching
/create_client validproxy usr_cert
/get_cert validproxy > /data/validproxy.pem
/get_key validproxy > /data/validproxy.pem.key

# Issue another valid certificate
/create_client valid2 usr_cert
/get_cert valid2 > /data/valid2.pem
/get_key valid2 > /data/valid2.pem.key

# Issue another and then revoke it
/create_client revoked usr_cert
/get_cert revoked > /data/revoked.pem
/get_key revoked > /data/revoked.pem.key
/revoke_client revoked

/get_crl > /data/kong.crl

# Output the CA for tests
/get_ca > /data/ca.pem

# Start the nginx to serve CRL
service nginx start

# Boot OCSP server interactive
openssl ocsp -port 2560 -text \
      -index /root/ca/intermediate/index.txt \
      -CA /root/ca/intermediate/certs/ca-chain.cert.pem \
      -rkey /root/ca/intermediate/private/oscp.key.pem \
      -rsigner /root/ca/intermediate/certs/oscp.cert.pem
