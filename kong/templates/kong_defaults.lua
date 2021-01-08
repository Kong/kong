-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

return [[
prefix = /usr/local/kong/
log_level = notice
proxy_access_log = logs/access.log
proxy_error_log = logs/error.log
admin_access_log = logs/admin_access.log
admin_error_log = logs/error.log
status_access_log = off
status_error_log = logs/status_error.log
plugins = bundled
port_maps = NONE
host_ports = NONE
anonymous_reports = on
go_pluginserver_exe = /usr/local/bin/go-pluginserver
go_plugins_dir = off

enforce_rbac = off
rbac_auth_header = Kong-Admin-Token
vitals = on
vitals_flush_interval = 10
vitals_delete_interval_pg = 30
vitals_ttl_seconds = 3600
vitals_ttl_minutes = 1500
vitals_ttl_days = 0

vitals_strategy = database
vitals_statsd_address = NONE
vitals_statsd_prefix = kong
vitals_statsd_udp_packet_size = 1024
vitals_tsdb_address = NONE
vitals_tsdb_user = NONE
vitals_tsdb_password = NONE
vitals_prometheus_scrape_interval = 5

portal = off
portal_is_legacy = off
portal_gui_listen = 0.0.0.0:8003, 0.0.0.0:8446 ssl
portal_gui_protocol = http
portal_gui_host = 127.0.0.1:8003
portal_cors_origins = NONE
portal_gui_use_subdomains = off
portal_gui_ssl_cert = NONE
portal_gui_ssl_cert_key = NONE
portal_gui_access_log = logs/portal_gui_access.log
portal_gui_error_log = logs/portal_gui_error.log

portal_api_listen = 0.0.0.0:8004, 0.0.0.0:8447 ssl
portal_api_url = NONE
portal_api_ssl_cert = NONE
portal_api_ssl_cert_key = NONE
portal_api_access_log = logs/portal_api_access.log
portal_api_error_log = logs/portal_api_error.log

portal_app_auth = kong-oauth2
portal_auto_approve = off
portal_auth = NONE
portal_auth_password_complexity =
portal_auth_conf = NONE
portal_auth_login_attempts = 0
portal_token_exp = 21600
portal_session_conf =

portal_email_verification = false
portal_invite_email = true
portal_access_request_email = true
portal_approved_email = true
portal_reset_email = true
portal_reset_success_email = true
portal_emails_from = NONE
portal_emails_reply_to = NONE

smtp_host = localhost
smtp_port = 25
smtp_starttls = off
smtp_username = NONE
smtp_password = NONE
smtp_ssl = off
smtp_auth_type = NONE
smtp_domain = localhost.localdomain
smtp_timeout_connect = 60000
smtp_timeout_send = 60000
smtp_timeout_read = 60000

proxy_url = NONE

audit_log = off
audit_log_record_ttl = 2592000
audit_log_ignore_methods =
audit_log_ignore_paths =
audit_log_ignore_tables =
audit_log_signing_key =
audit_log_payload_exclude = token, secret, password

proxy_listen = 0.0.0.0:8000 reuseport backlog=16384, 0.0.0.0:8443 http2 ssl reuseport backlog=16384
stream_listen = off

admin_api_uri = NONE
admin_gui_listen = 0.0.0.0:8002, 0.0.0.0:8445 ssl
admin_gui_url =
admin_gui_access_log = logs/admin_gui_access.log
admin_gui_error_log = logs/admin_gui_error.log
admin_gui_flags = {}
admin_gui_auth =
admin_gui_auth_conf =
admin_gui_auth_header = Kong-Admin-User
admin_gui_auth_password_complexity =
admin_gui_session_conf =
admin_gui_auth_login_attempts = 0
admin_approved_email = true
admin_emails_from = ""
admin_emails_reply_to = NONE
admin_invitation_expiry = 259200

admin_listen = 127.0.0.1:8001 reuseport backlog=16384, 127.0.0.1:8444 http2 ssl reuseport backlog=16384
status_listen = off
cluster_listen = 0.0.0.0:8005
cluster_control_plane = 127.0.0.1:8005
cluster_cert = NONE
cluster_cert_key = NONE
cluster_mtls = shared
cluster_ca_cert = NONE
cluster_server_name = NONE
cluster_data_plane_purge_delay = 1209600
mem_cache_size = 128m
ssl_cert = NONE
ssl_cert_key = NONE
client_ssl = off
client_ssl_cert = NONE
client_ssl_cert_key = NONE
ssl_cipher_suite = intermediate
ssl_ciphers = NONE
ssl_protocols = TLSv1.1 TLSv1.2 TLSv1.3
ssl_prefer_server_ciphers = on
ssl_dhparam = NONE
ssl_session_tickets = on
ssl_session_timeout = 1d
admin_ssl_cert = NONE
admin_ssl_cert_key = NONE
status_ssl_cert = NONE
status_ssl_cert_key = NONE
headers = server_tokens, latency_tokens
trusted_ips = NONE
error_default_type = text/plain
upstream_keepalive = NONE
upstream_keepalive_pool_size = 60
upstream_keepalive_max_requests = 100
upstream_keepalive_idle_timeout = 60

admin_gui_ssl_cert = NONE
admin_gui_ssl_cert_key = NONE

nginx_user = kong kong
nginx_worker_processes = auto
nginx_optimizations = on
nginx_daemon = on
nginx_main_daemon = on
nginx_main_user = kong kong
nginx_main_worker_processes = auto
nginx_main_worker_rlimit_nofile = auto
nginx_events_worker_connections = auto
nginx_events_multi_accept = on
nginx_http_client_max_body_size = 0
nginx_http_client_body_buffer_size = 8k
nginx_http_ssl_protocols = NONE
nginx_http_ssl_prefer_server_ciphers = NONE
nginx_http_ssl_dhparam = NONE
nginx_http_ssl_session_tickets = NONE
nginx_http_ssl_session_timeout = NONE
nginx_stream_ssl_protocols = NONE
nginx_stream_ssl_prefer_server_ciphers = NONE
nginx_stream_ssl_dhparam = NONE
nginx_stream_ssl_session_tickets = NONE
nginx_stream_ssl_session_timeout = NONE
nginx_proxy_real_ip_header = X-Real-IP
nginx_proxy_real_ip_recursive = off
nginx_admin_client_max_body_size = 10m
nginx_admin_client_body_buffer_size = 10m
nginx_upstream_keepalive = NONE
nginx_upstream_keepalive_requests = NONE
nginx_upstream_keepalive_timeout = NONE
nginx_http_upstream_keepalive = NONE
nginx_http_upstream_keepalive_requests = NONE
nginx_http_upstream_keepalive_timeout = NONE

client_max_body_size = 0
client_body_buffer_size = 8k
real_ip_header = X-Real-IP
real_ip_recursive = off

database = postgres

pg_host = 127.0.0.1
pg_port = 5432
pg_database = kong
pg_schema = NONE
pg_timeout = 5000
pg_user = kong
pg_password = NONE
pg_ssl = off
pg_ssl_required = off
pg_ssl_verify = off
pg_ssl_version = tlsv1
pg_ssl_cert = NONE
pg_ssl_cert_key = NONE
pg_max_concurrent_queries = 0
pg_semaphore_timeout = 60000
pg_keepalive_timeout = 60000

pg_ro_host = NONE
pg_ro_port = NONE
pg_ro_database = NONE
pg_ro_schema = NONE
pg_ro_timeout = NONE
pg_ro_user = NONE
pg_ro_password = NONE
pg_ro_ssl = NONE
pg_ro_ssl_required = NONE
pg_ro_ssl_verify = NONE
pg_ro_ssl_version = NONE
pg_ro_max_concurrent_queries = NONE
pg_ro_semaphore_timeout = NONE
pg_ro_keepalive_timeout = NONE

cassandra_contact_points = 127.0.0.1
cassandra_port = 9042
cassandra_keyspace = kong
cassandra_timeout = 5000
cassandra_ssl = off
cassandra_ssl_verify = off
cassandra_username = kong
cassandra_password = NONE
cassandra_consistency = NONE
cassandra_write_consistency = ONE
cassandra_read_consistency = ONE
cassandra_lb_policy = RequestRoundRobin
cassandra_local_datacenter = NONE
cassandra_refresh_frequency = 60
cassandra_repl_strategy = SimpleStrategy
cassandra_repl_factor = 1
cassandra_data_centers = dc1:2,dc2:3
cassandra_schema_consensus_timeout = 10000

declarative_config = NONE

db_update_frequency = 5
db_update_propagation = 0
db_cache_ttl = 0
db_cache_neg_ttl = NONE
db_resurrect_ttl = 30
db_cache_warmup_entities = services

dns_resolver = NONE
dns_hostsfile = /etc/hosts
dns_order = LAST,SRV,A,CNAME
dns_valid_ttl = NONE
dns_stale_ttl = 4
dns_not_found_ttl = 30
dns_error_ttl = 1
dns_no_sync = off

worker_consistency = strict
worker_state_update_frequency = 5

lua_socket_pool_size = 30
lua_ssl_trusted_certificate = NONE
lua_ssl_verify_depth = 1
lua_package_path = ./?.lua;./?/init.lua;
lua_package_cpath = NONE

feature_conf_path = NONE

smtp_admin_emails = NONE
smtp_mock = on

tracing = off
tracing_write_endpoint =
tracing_write_strategy = file
tracing_time_threshold = 0
tracing_types = all
tracing_debug_header =
generate_trace_details = off
route_validation_strategy = smart
enforce_route_path_pattern = NONE

keyring_enabled = off
keyring_blob_path =
keyring_public_key =
keyring_private_key =
keyring_strategy = cluster
keyring_vault_host =
keyring_vault_mount =
keyring_vault_path =
keyring_vault_token =


event_hooks_enabled = off

role = traditional
kic = off
pluginserver_names = NONE

cluster_telemetry_listen = 0.0.0.0:8006
cluster_telemetry_endpoint = 127.0.0.1:8006
cluster_telemetry_server_name = NONE

untrusted_lua = on
untrusted_lua_sandbox_requires =
untrusted_lua_sandbox_environment =
]]
