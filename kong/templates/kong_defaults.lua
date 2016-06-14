return [[
prefix = /usr/local/kong/
log_level = notice
custom_plugins = NONE
anonymous_reports = on

proxy_listen = 0.0.0.0:8000
proxy_listen_ssl = 0.0.0.0:8443
admin_listen = 0.0.0.0:8001
nginx_worker_processes = auto
nginx_optimizations = on
nginx_daemon = on
mem_cache_size = 128m
ssl = on
ssl_cert = NONE
ssl_cert_key = NONE

database = postgres
pg_host = 127.0.0.1
pg_port = 5432
pg_database = kong
pg_user = kong
pg_password = NONE
cassandra_contact_points = 127.0.0.1
cassandra_port = 9042
cassandra_keyspace = kong
cassandra_repl_strategy = SimpleStrategy
cassandra_repl_factor = 1
cassandra_data_centers = dc1:2,dc2:3
cassandra_consistency = ONE
cassandra_timeout = 5000
cassandra_ssl = off
cassandra_ssl_verify = off
cassandra_ssl_trusted_cert = NONE
cassandra_username = kong
cassandra_password = NONE

cluster_listen = 0.0.0.0:7946
cluster_listen_rpc = 127.0.0.1:7373
cluster_advertise = NONE
cluster_encrypt_key = NONE
cluster_ttl_on_failure = 3600

dnsmasq = on
dnsmasq_port = 8053
dns_resolver = NONE

lua_code_cache = on
lua_package_path = ?/init.lua;./kong/?.lua
]]
