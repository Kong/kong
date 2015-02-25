#!/bin/bash

source $(dirname $0)/base_screencast.sh

# Preparation commands

docker stop cassandra > /dev/null 2>&1
docker rm cassandra > /dev/null 2>&1
docker rmi mashape/docker-cassandra > /dev/null 2>&1

docker stop kong > /dev/null 2>&1
docker rm kong > /dev/null 2>&1
docker rmi mashape/docker-kong:0.0.1-beta > /dev/null 2>&1

# Actual screencast

slow_echo "# Let's start Kong using Docker"
slow_echo "# Kong requires a Cassandra instance to be running"
slow_echo "# so let's download and run the Cassandra Docker container first"

exec_cmd "docker run -p 9042:9042 -d --name cassandra mashape/docker-cassandra"

slow_echo "# Cassandra is now up and running:"
exec_cmd "docker ps"

slow_echo "# We can now download and run the Kong container:"
exec_cmd "docker run -p 8000:8000 -p 8001:8001 -d --name kong --link cassandra:cassandra mashape/docker-kong:0.0.1-beta"
slow_echo "# Now that both Cassandra and Kong are running"
slow_echo "# we can try to make a request to Kong to see if"
slow_echo "# everything is okay. Kong listens to port 8000 for"
slow_echo "# the API server, and port 8001 for the admin API"
exec_cmd "curl 127.0.0.1:8000"
slow_echo "# Success! This error message is returned by Kong"
slow_echo "# because we didn't setup any API yet, as we can see by"
slow_echo "# invoking Kong's administration API on port 8001"
exec_cmd "curl 127.0.0.1:8001/apis/"
slow_echo "# Yep, no APIs found. Kong is now ready to be used!"
slow_echo ""
