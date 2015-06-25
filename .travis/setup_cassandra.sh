#!/bin/bash

CASSANDRA_BASE=apache-cassandra-$CASSANDRA_VERSION

rm -rf /var/lib/cassandra/*
curl http://apache.spinellicreations.com/cassandra/$CASSANDRA_VERSION/$CASSANDRA_BASE-bin.tar.gz | tar xz
sh $CASSANDRA_BASE/bin/cassandra
