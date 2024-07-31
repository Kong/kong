#!/bin/sh
openssl ca -config /root/ca/intermediate/openssl.cnf \
      -gencrl