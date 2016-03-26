return [[
admin_listen = 0.0.0.0:8001
proxy_listen = 0.0.0.0:8000
proxy_listen_ssl = 0.0.0.0:8443

cluster_listen = 0.0.0.0:7946
cluster_listen_rpc = 127.0.0.1:7373
cluster_advertise = NONE
cluster_secret = NONE

dnsmasq = on
dns_resolver = 127.0.0.1:8053

database = postgres

pg_host = 127.0.0.1
pg_port = 5432
pg_user = kong
pg_password = kong
pg_database = kong

cassandra_contact_points = 127.0.0.1:9042
cassandra_keyspace = kong
cassandra_repl_strategy = SimpleStrategy
cassandra_repl_factor = 1
cassandra_data_centers = dc1:2,dc2:3
cassandra_timeout = 5000
cassandra_consistency = ONE
cassandra_ssl = off
cassandra_ssl_verify = off
cassandra_ssl_ca = NONE
cassandra_username = kong
cassandra_password = kong

ssl_cert = NONE
ssl_key = NONE

anonymous_reports = on
mem_cache_size = 128m

lua_code_cache = on
lua_package_path = ?/init.lua;./kong/?.lua

nginx_daemon = on
nginx_worker_processes = auto
]]
