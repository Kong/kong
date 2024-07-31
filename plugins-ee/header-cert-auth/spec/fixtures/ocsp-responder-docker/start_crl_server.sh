#!/bin/sh
#
cp /root/ca/intermediate/crl/intermediate.crl.pem /var/www/kong.crl

service nginx start
