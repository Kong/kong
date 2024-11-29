#!/usr/bin/env bash

echo "Stopping previously running Kong"

kong stop
  
pid_file=servroot/pids/nginx.pid
while [ -f $pid_file ]
do
    if kill -0 "$(cat $pid_file)" >/dev/null 2>&1
    then
        sleep 1
    else
        break
    fi
done

set -e

rm -f /tmp/appd/* servroot/logs/error.log

if [ "$KONG_APPD_CONTROLLER_ACCESS_KEY" = "" ]
then
    echo "Missing KONG_APPD_CONTROLLER_ACCESS_KEY variable, cannot continue"
    exit 1
fi

# Number of normal and successful transactions to send
NORMAL_TRANSACTION_COUNT=100

export KONG_APPD_NODE_NAME=${KONG_APPD_NODE_NAME:-$(hostname)}          \
       LD_LIBRARY_PATH=ld_lib                                           \
       KONG_APPD_LOGGING_LEVEL=0                                        \
       KONG_APPD_CONTROLLER_HOST=kong-nfr.saas.appdynamics.com          \
       KONG_APPD_CONTROLLER_ACCOUNT=kong-nfr                            \
       KONG_DATABASE=postgres                                           \
       KONG_PLUGINS=app-dynamics                                        \
       KONG_APPD_TIER_NAME=${KONG_APPD_TIER_NAME:-KongTier}             \
       KONG_APPD_SERVICE_NAME=${KONG_APPD_SERVICE_NAME:-KongService}

echo "Starting Kong, AppDynamics node name: $KONG_APPD_NODE_NAME, service name"

KONG_PLUGINS=app-dynamics,bundled kong start --conf=spec/kong_tests.conf --nginx-conf=spec/fixtures/custom_nginx.template

sleep 5

echo "Adding route and plugin to service"

service_id=$(http :9001/services | jq -r '.data[0].id')
http -p h put :9001/services/$service_id        \
     'host=127.0.0.1'                           \
     'port:=15555'                              \
     'protocol=http'                            \
     'retries:=0'                               \
     'read_timeout:=600000'                     \
     "name=${KONG_APPD_SERVICE_NAME}"
http -p h :9001/services/$service_id/routes     \
     'hosts[0]=test1.com'                       \
     'paths[0]=/request'                        \
     "paths[1]=/delay"                          \
     "paths[2]=/does-not-exist"
http -p h :9001/services/$service_id/plugins    \
     'name=app-dynamics'

http -p h :9001/services/$service_id/plugins    \
     'name=key-auth'                            \
     'config.key_names[0]=apikey'

http -p h :9001/consumers                       \
     'username=alex'

http -p h :9001/consumers/alex/key-auth        \
     'key=alex'

sleep 5

echo "Sending $NORMAL_TRANSACTION_COUNT successful requests: "

for i in $(seq $NORMAL_TRANSACTION_COUNT)
do
    singularity_header=$(http -p b :9000/request?apikey=alex host:test1.com | jq -r .headers.singularityheader)
    if ! [[ $singularity_header =~ appId=([^*]+).*cidfrom=([^*]+) ]]
    then
        echo
        echo "Singularity header does not contain the expected tags: $singularity_header"
        exit 1
    fi
    echo -n '.'

    if [ "$appdynamics_url" = "" ]
    then
        application=${BASH_REMATCH[1]}
        component=${BASH_REMATCH[2]}
        appdynamics_url="https://$KONG_APPD_CONTROLLER_ACCOUNT.saas.appdynamics.com/controller/#/location=APP_COMPONENT_INFRASTRUCTURE&timeRange=last_1_hour.BEFORE_NOW.-1.-1.60&application=$application&component=$component"
    fi
done
echo

echo "Sending unsuccessful request"

singularity_header=$(http -p b :9000/does-not-exist?apikey=alex host:test1.com | jq -r .headers.singularityheader)
if ! [[ $singularity_header =~ appId ]]
then
    echo "Singularity header does not contain the expected tags: $singularity_header"
    exit 1
fi

echo "Sending request with very slow response (5 minutes!)"

singularity_header=$(http -p b :9000/delay/20?apikey=alex host:test1.com | jq -r .headers.singularityheader)
if ! [[ $singularity_header =~ appId ]]
then
    echo "Singularity header does not contain the expected tags: $singularity_header"
    exit 1
fi

echo "Waiting for the SDK to propagate the calls to AppDynamics"
sleep 60
echo "Please go to $appdynamics_url"
echo "Your testing node name is $KONG_APPD_NODE_NAME, your tier name is $KONG_APPD_TIER_NAME"
echo "Verify that there are $NORMAL_TRANSACTION_COUNT normal transactions,"
echo "one error transaction and one very long transaction visible"
