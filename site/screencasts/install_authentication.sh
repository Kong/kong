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

sleep 5

curl -d "name=HttpBin&public_dns=myapi.com&target_url=http://httpbin.org" 127.0.0.1:8001/apis/ > /dev/null 2>&1

# Actual screencast

slow_echo "# By adding an API on Kong creates a proxy mapping"
slow_echo "# between the \"public_dns\" and the \"target_url\" so that"
slow_echo "# Kong knows how to process requests and where to proxy them."
slow_echo ""
slow_echo "# By default Kong doesn't do anything more, unless we install"
slow_echo "# Kong Plugins on top of the API. That is the beautiful part :)"
slow_echo ""
slow_echo "# For example, let's add an api-key authentication to an API."
slow_echo "# We have one API added in the system:"

exec_cmd "curl 127.0.0.1:8001/apis/"

output=$(curl -s 127.0.0.1:8001/apis/)
api_id=$(extract_id $output "id")

slow_echo "# Right now the API has no Plugins installed, so we can freely use it:"

exec_cmd "curl -H \"Host: myapi.com:\" 127.0.0.1:8000/get"

slow_echo "# In order to add an authentication plugin to this API"
slow_echo "# we need to create a new Plugin object using the"
slow_echo "# administration API at the following URL:"

exec_cmd "curl -XPOST 127.0.0.1:8001/plugins/"

slow_echo "# As you can see we need some required parameters:"
slow_echo "# \"name\" is the name of the plugin to install, in our"
slow_echo "# case it's \"authentication\". \"api_id\" is the API that we're"
slow_echo "# targeting, and \"value\" is the configuration value of the Plugin."
slow_echo ""
slow_echo "# Each Plugin has it's own configuration."
slow_echo "# So, let's add the authentication Plugin:"

exec_cmd "curl -XPOST -d 'name=authentication&api_id=$api_id&value={\"authentication_type\":\"query\",\"authentication_key_names\":[\"apikey\"]}' 127.0.0.1:8001/plugins/"

slow_echo "The authentication Plugin has now been installed on the API with"
slow_echo "a configuration that sets the \"authentication_type\" to \"query\""
slow_echo "and the parameter name \"authentication_key_names\" to \"apikey\""
slow_echo "Let's try to consume the API again:"

exec_cmd "curl -H \"Host: myapi.com:\" 127.0.0.1:8000/get"

slow_echo "And as you can see Kong is now blocking the request"
slow_echo "because we're not autheticated and we didn't send any credentials"
slow_echo "along with the request."
slow_echo ""
slow_echo "In Kong adding/configuring/removing Plugins is as easy as executing"
slow_echo "one HTTP request using Kong's administration API"
slow_echo ":)"

slow_echo ""
