#!/bin/bash -x
#This entrypoint is responsible for leaving the OSCP running to accept requests

for type in ocsp crl
do
    # issue certificates
    for cert in valid revoked
    do
        /create_client $type $cert
        /get_cert $type-$cert > /data/$type-$cert.pem
        /get_cert_and_intermediate $type-$cert > /data/$type-$cert-inter.pem
        /get_key $type-$cert > /data/$type-$cert.pem.key
    done

    # revoke the certificates
    for cert in revoked revoked2 revoked3
    do
        /revoke_client $type-$cert
    done
done

# Output the CA for tests
/get_ca > /data/ca.pem
/get_intermediate > /data/intermediate.pem

# Boot CRL nginx server
/start_crl_server

# Boot OCSP server interactive
openssl ocsp -port 2560 -text \
      -index /root/ca/intermediate/index.txt \
      -CA /root/ca/intermediate/certs/ca-chain.cert.pem \
      -rkey /root/ca/intermediate/private/oscp.key.pem \
      -rsigner /root/ca/intermediate/certs/oscp.cert.pem
