#!/bin/bash

CASSANDRA_BASE=apache-cassandra-$CASSANDRA_VERSION

n=0
until [ $n -ge 5 ]
do
    sudo rm -rf /var/lib/cassandra/*
    curl http://archive.apache.org/dist/cassandra/$CASSANDRA_VERSION/$CASSANDRA_BASE-bin.tar.gz | tar xz && break
    n=$[$n+1]
    sleep 5
done

if [[ ! -f $CASSANDRA_BASE/bin/cassandra ]] ; then
    echo 'Failed downloading and unpacking cassandra. Aborting.'
    exit 1
fi

sudo sh $CASSANDRA_BASE/bin/cassandra
