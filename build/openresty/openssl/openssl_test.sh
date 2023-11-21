#!/usr/bin/env bash

if [[ ! -e "$OPENSSL" ]]; then
    echo "openssl does not exist"
    exit 1
fi

exec $OPENSSL help
