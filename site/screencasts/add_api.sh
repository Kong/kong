#!/bin/bash

source $(dirname $0)/base_screencast.sh

# Preparation commands

docker stop cassandra > /dev/null 2>&1
docker rm cassandra > /dev/null 2>&1
docker rmi mashape/docker-cassandra > /dev/null 2>&1

docker stop kong > /dev/null 2>&1
docker rm kong > /dev/null 2>&1
docker rmi mashape/docker-kong:0.0.1-beta > /dev/null 2>&1

docker run -p 9042:9042 -d --name cassandra mashape/docker-cassandra > /dev/null 2>&1
docker run -p 8000:8000 -p 8001:8001 -d --name kong --link cassandra:cassandra mashape/docker-kong:0.0.1-beta > /dev/null 2>&1

# Actual screencast

slow_echo "# Now that we have both Cassandra and Kong running"
slow_echo "# we can start configuring Kong using its RESTful API"
slow_echo "# and add our fist API to it."
slow_echo ""
slow_echo "# If we try to consume Kong now, it will tell us that"
slow_echo "# the API cannot be found. That's because Kong can't"
slow_echo "# map the requested Host to any API in the system:"

exec_cmd "curl 127.0.0.1:8000"

slow_echo "# So let's add our first API to Kong. For this example we will"
slow_echo "# be using httpbin.org as the API to put behind Kong."
slow_echo ""
slow_echo "# In order to add a new API we will use Kong's admin API,"
slow_echo "# that by default listens on port 8001."

exec_cmd "curl -XPOST 127.0.0.1:8001/apis/"

slow_echo "# The API call to add a new API on Kong returned an error"
slow_echo "# because we didn't send any required parameter"
slow_echo "# In order to add the API Kong needs to know three parameters:"
slow_echo "# The \"name\" of the API, the \"public_dns\" where the API will be"
slow_echo "# reachable by clients, and the \"target_url\" that is the final"
slow_echo "# location of the API that Kong will proxy requests to."
slow_echo ""
slow_echo "So for example let's add HttpBin on Kong and let's say that"
slow_echo "we want to make it available at myapi.com"

exec_cmd "curl -XPOST -d \"name=HttpBin&public_dns=myapi.com&target_url=http://httpbin.org\" 127.0.0.1:8001/apis/"

slow_echo "The API has been now added on Kong."
slow_echo "We can list all the APIs added by making the following request"

exec_cmd "curl 127.0.0.1:8001/apis/"

slow_echo "In production we would point myapi.com to kong or to its load balancer"
slow_echo "And Kong will resolve every request to myapi.com and proxy it to HttpBin"
slow_echo ""
slow_echo "Since here in this test we don't have a load balancer"
slow_echo "We'll trick Kong and make it think that the request has been made"
slow_echo "to myapi.com"

exec_cmd "curl -H \"Host: myapi.com:\" 127.0.0.1:8000/get"

slow_echo "Success! The request has been properly proxied to HttpBin!"
slow_echo "In production ,with a proper DNS configuration, the same request"
slow_echo "could be made by consuming http://myapi.com/get"
slow_echo ""
slow_echo "As you see the path of the request is being appended"
slow_echo "to the \"target_url\" property"
slow_echo ""
slow_echo "We can try to make a POST request too:"

exec_cmd "curl -XPOST -d \"name=Mark\" -H \"Host: myapi.com:\" 127.0.0.1:8000/post"

slow_echo "We have added our first API to Kong :)"
slow_echo ""
