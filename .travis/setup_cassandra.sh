#!/bin/bash

CASSANDRA_BASE=apache-cassandra-$CASSANDRA

sudo rm -rf /var/lib/cassandra/*
curl http://www.us.apache.org/dist/cassandra/2.1.2/$CASSANDRA_BASE-bin.tar.gz | tar xz
sudo sh $CASSANDRA_BASE/bin/cassandra
