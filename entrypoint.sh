#!/usr/bin/env bash

if [[ "$KONG_DATABASE" =~ postgres ]]; then
  /wait-for-it.sh $KONG_PG_HOST:5432
else
  /wait-for-it.sh $KONG_CASSANDRA_CONTACT_POINTS:7000 
fi

printenv | grep KONG
make dev
/kong/bin/kong prepare
/kong/bin/kong migrations up && echo 'done' && tail -f /dev/null