return [[
prefix = /usr/local/kong/
log_level = notice
proxy_access_log = logs/access.log
proxy_error_log = logs/error.log
admin_access_log = logs/admin_access.log
admin_error_log = logs/error.log
plugins = bundled
anonymous_reports = on
enforce_rbac = off
rbac_auth_header = Kong-Admin-Token
vitals = on
vitals_flush_interval = 10
vitals_delete_interval_pg = 30
vitals_ttl_seconds = 3600
vitals_ttl_minutes = 90000

vitals_strategy = database
vitals_statsd_address = NONE
vitals_statsd_prefix = kong
vitals_statsd_udp_packet_size = 1024
vitals_tsdb_address = NONE
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

portal_api_listen = 0.0.0.0:8004, 0.0.0.0:8447 ssl
portal_api_url = NONE
portal_api_ssl_cert = NONE
portal_api_ssl_cert_key = NONE
portal_api_access_log = logs/portal_api_access.log
portal_api_error_log = logs/error.log

portal_auto_approve = off
portal_auth = NONE
portal_auth_conf = NONE
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

proxy_listen = 0.0.0.0:8000, 0.0.0.0:8443 ssl
stream_listen = off
admin_listen = 127.0.0.1:8001, 127.0.0.1:8444 ssl

admin_api_uri = NONE
admin_gui_listen = 0.0.0.0:8002, 0.0.0.0:8445 ssl
admin_gui_url =
admin_gui_access_log = logs/admin_gui_access.log
admin_gui_error_log = logs/admin_gui_error.log
admin_gui_flags = {}
admin_gui_auth =
admin_gui_auth_conf =
admin_gui_auth_header = Kong-Admin-User
admin_gui_session_conf =
admin_gui_auth_login_attempts = 0
admin_approved_email = true
admin_emails_from = ""
admin_emails_reply_to = NONE
admin_docs_url = https://docs.konghq.com/enterprise/0.34/admin-gui/overview/
admin_invitation_expiry = 259200

origins = NONE
nginx_user = nobody nobody
nginx_worker_processes = auto
nginx_optimizations = on
nginx_daemon = on
mem_cache_size = 128m
ssl_cert = NONE
ssl_cert_key = NONE
client_ssl = off
client_ssl_cert = NONE
client_ssl_cert_key = NONE
ssl_cipher_suite = modern
ssl_ciphers = ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-SHA384:ECDHE-RSA-AES256-SHA384:ECDHE-ECDSA-AES128-SHA256:ECDHE-RSA-AES128-SHA256
admin_ssl_cert = NONE
admin_ssl_cert_key = NONE
admin_gui_ssl_cert = NONE
admin_gui_ssl_cert_key = NONE
upstream_keepalive = 60
headers = server_tokens, latency_tokens
trusted_ips = NONE
real_ip_header = X-Real-IP
real_ip_recursive = off
client_max_body_size = 0
client_body_buffer_size = 8k
error_default_type = text/plain

nginx_http_ssl_protocols = TLSv1.1 TLSv1.2 TLSv1.3
nginx_http_upstream_keepalive = 60
nginx_http_upstream_keepalive_requests = 100
nginx_http_upstream_keepalive_timeout = 60s

database = postgres
pg_host = 127.0.0.1
pg_port = 5432
pg_database = kong
pg_schema = NONE
pg_timeout = 5000
pg_user = kong
pg_password = NONE
pg_ssl = off
pg_ssl_verify = off
pg_max_concurrent_queries = 0
pg_semaphore_timeout = 60000
cassandra_contact_points = 127.0.0.1
cassandra_port = 9042
cassandra_keyspace = kong
cassandra_timeout = 5000
cassandra_ssl = off
cassandra_ssl_verify = off
cassandra_username = kong
cassandra_password = NONE
cassandra_consistency = ONE
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
db_resurrect_ttl = 30
db_cache_warmup_entities = services, plugins

dns_resolver = NONE
dns_hostsfile = /etc/hosts
dns_order = LAST,SRV,A,CNAME
dns_valid_ttl = NONE
dns_stale_ttl = 4
dns_not_found_ttl = 30
dns_error_ttl = 1
dns_no_sync = off

router_consistency = strict

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
]]
