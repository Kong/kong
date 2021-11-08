#!/bin/sh
#This entrypoint is responsible for leaving the OSCP running to accept requests
openssl ocsp -port 2560 -text \
      -index /root/ca/intermediate/index.txt \
      -CA /root/ca/intermediate/certs/ca-chain.cert.pem \
      -rkey /root/ca/intermediate/private/oscp.key.pem \
      -rsigner /root/ca/intermediate/certs/oscp.cert.pem