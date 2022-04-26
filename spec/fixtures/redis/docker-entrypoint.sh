#!/bin/sh
set -e

if [ -d /workspace ] ;  then
    redis-server                                                    \
        --tls-port 6380                                             \
        --tls-cert-file /workspace/spec/fixtures/redis/server.crt   \
        --tls-key-file /workspace/spec/fixtures/redis/server.key    \
        --tls-cluster no                                            \
        --tls-replication no                                        \
        --tls-auth-clients no
fi

tail -f /dev/null