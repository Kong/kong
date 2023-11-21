#!/usr/bin/env bash

pg_conf_file=/var/lib/postgresql/data/postgresql.conf

echo "\
log_statement = 'all'
log_disconnections = off
log_duration = on
log_min_duration_statement = -1
shared_preload_libraries = 'pg_stat_statements'
track_activity_query_size = 2048
pg_stat_statements.track = all
pg_stat_statements.max = 10000
" >>$pg_conf_file

for database in $(echo $POSTGRES_DBS | tr ',' ' '); do
  echo "Creating database $database"
  psql -U $POSTGRES_USER <<-EOSQL
    SELECT 'CREATE DATABASE $database' WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '$database')\gexec
    GRANT ALL PRIVILEGES ON DATABASE $database TO $POSTGRES_USER;
EOSQL
done
