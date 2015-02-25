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
output=$(curl -s 127.0.0.1:8001/apis/)
api_id=$(extract_id $output "id")
curl -d "name=authentication&api_id=$api_id&value={\"authentication_type\":\"query\",\"authentication_key_names\":[\"apikey\"]}" 127.0.0.1:8001/plugins/ > /dev/null 2>&1

# Actual screencast

slow_echo "# In this screencast we already have an API configured"
slow_echo "# on Kong, with the Authentication plugin installed."
slow_echo ""
slow_echo "# If we try to make a request to the API, Kong tells us"
slow_echo "# that we didn't provide the right credentials for consuming it."

exec_cmd "curl -H \"Host: myapi.com:\" 127.0.0.1:8000/get"

slow_echo "# To create the credentials we need to create both"
slow_echo "# an Account and an Application. An Account on Kong"
slow_echo "# represents a user, and an Account can have many"
slow_echo "# Applications. The Application is what ultimately"
slow_echo "# stores the credentials the user is going to use when"
slow_echo "# consuming the API."
slow_echo ""
slow_echo "# So let's go ahead and create an Account:"

exec_cmd "curl -XPOST 127.0.0.1:8001/accounts/"

output=$(curl -s 127.0.0.1:8001/accounts/)
account_id=$(extract_id $output "id")

slow_echo "# An account can optionally be associated with a custom ID"
slow_echo "# that you can provide to map it with your existing datastore"
slow_echo ""
slow_echo "# Now that we've created an Account, we can create an Application"

exec_cmd "curl -d \"account_id=$account_id&public_key=apikey1234\" -XPOST 127.0.0.1:8001/applications/"

slow_echo "# We have created an Application whose \"public_key\" is set"
slow_echo "# to \"apikey1234\", which is the api-key the client will need"
slow_echo "# to use when consuming the API"
slow_echo ""
slow_echo "# So let's try to consume the API again, passing the api-key:"

exec_cmd "curl -H \"Host: myapi.com:\" 127.0.0.1:8000/get?apikey=apikey1234"

slow_echo "# It worked! Kong successfully authenticated the request :)"

slow_echo ""
