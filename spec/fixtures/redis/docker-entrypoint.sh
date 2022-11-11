#!/bin/sh
set -e

echo "Kong CI redis container..."

if [ -d /workspace ] ;  then
    echo "Starting test server..."

    redis-server                                                    \
        --tls-port 6380                                             \
        --tls-cert-file /workspace/spec/fixtures/redis/server.crt   \
        --tls-key-file /workspace/spec/fixtures/redis/server.key    \
        --tls-cluster no                                            \
        --tls-replication no                                        \
        --tls-auth-clients no
fi

tail -f /dev/null