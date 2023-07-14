#!/bin/bash

cd /root/ca
mkdir /root/ca/certs /root/ca/crl /root/ca/newcerts private
#Read and write to root in private folder
chmod 700 private
touch /root/ca/index.txt
#Echo the user id
echo 1000 > /root/ca/serial
#Generating the root key for the Certificate Authority | For simplicity without passphrase for usage within docker
openssl genrsa -out /root/ca/private/ca.key.pem 4096
#Read-only rights to the running user , root in this cases, as there is no need for any changes to the Dockerfile to declare another user and simplicity
chmod 400 /root/ca/private/ca.key.pem
#Now let's create the certificate for the authority and pass along the subject as will be ran in non-interactive mode
openssl req -config /root/ca/openssl.cnf \
      -key /root/ca/private/ca.key.pem \
      -new -x509 -days 3650 -sha256 -extensions v3_ca \
      -out /root/ca/certs/ca.cert.pem \
      -subj "/C=US/ST=CA/L=SF/O=kong/OU=FTT/CN=www.root.kong.com/EMAIL=root@konghq.com"

echo "Created Root Certificate"
#Grant everyone reading rights
chmod 444 /root/ca/certs/ca.cert.pem

#Now that we created the root pair, we should use and intermediate one.
#This part is the same as above except for the folder
mkdir /root/ca/intermediate/certs /root/ca/intermediate/crl /root/ca/intermediate/csr /root/ca/intermediate/newcerts /root/ca/intermediate/private
chmod 700 /root/ca/intermediate/private
touch /root/ca/intermediate/index.txt
#We must create a serial file to add serial numbers to our certificates - This will be useful when revoking as well
echo 1000 > /root/ca/intermediate/serial
echo 1000 > /root/ca/intermediate/crlnumber
touch /root/ca/intermediate/certs.db

openssl genrsa -out /root/ca/intermediate/private/intermediate.key.pem 4096
chmod 400 /root/ca/intermediate/private/intermediate.key.pem

echo "Created Intermediate Private Key"

#Creating the intermediate certificate signing request using the intermediate ca config
openssl req -config intermediate/openssl.cnf \
      -key /root/ca/intermediate/private/intermediate.key.pem \
      -new -sha256 \
      -out /root/ca/intermediate/csr/intermediate.csr.pem \
      -subj "/C=US/ST=CA/L=SF/O=kong/OU=FTT/CN=www.intermediate.kong.com/EMAIL=intermediate@konghq.com"

echo "Created Intermediate CSR"

#Creating an intermediate certificate, by signing the previous csr with the CA key based on root ca config with the directive v3_intermediate_ca extension to sign the intermediate CSR
echo -e "y\ny\n" | openssl ca -batch -config openssl.cnf -extensions v3_intermediate_ca \
      -days 3650 -notext -md sha256 \
      -in /root/ca/intermediate/csr/intermediate.csr.pem \
      -out /root/ca/intermediate/certs/intermediate.cert.pem

echo "Created Intermediate Certificate Signed by root CA"

#Grant everyone reading rights
chmod 444 /root/ca/intermediate/certs/intermediate.cert.pem


#Creating certificate chain with intermediate and root
cat /root/ca/intermediate/certs/intermediate.cert.pem \
      /root/ca/certs/ca.cert.pem > /root/ca/intermediate/certs/ca-chain.cert.pem
chmod 444 /root/ca/intermediate/certs/ca-chain.cert.pem


#Create a Certificate revocation list of the intermediate CA
openssl ca -batch -config /root/ca/intermediate/openssl.cnf \
      -gencrl -out /root/ca/intermediate/crl/intermediate.crl.pem

#Create OSCP key pair
openssl genrsa \
      -out /root/ca/intermediate/private/oscp.key.pem 4096

#Create the OSCP CSR
openssl req -config /root/ca/intermediate/openssl.cnf -new -sha256 \
      -key /root/ca/intermediate/private/oscp.key.pem \
      -out /root/ca/intermediate/csr/oscp.csr.pem \
      -nodes \
      -subj "/C=US/ST=CA/L=SF/O=kong/OU=FTT/CN=www.ocsp.kong.com/EMAIL=ocsp@konghq.com"

#Sign it
echo -e "y\ny\n" | openssl ca -batch -config /root/ca/intermediate/openssl.cnf \
      -extensions ocsp -days 375 -notext -md sha256 \
      -in /root/ca/intermediate/csr/oscp.csr.pem \
      -out /root/ca/intermediate/certs/oscp.cert.pem
