local buffer = require "string.buffer"


local options = {
  dict = { "X-Cache-Key", "X-Cache-Status", "absolute_timeout", "accept_http_if_already_terminated", "access", "access_token", "account_email", "account_key", "active", "add", "age", "algorithm", "algorithms", "allow", "allow_any_domain", "allow_origin_header", "allow_status_codes", "allowed_payload_size", "anonymous", "api_uri", "apikey", "append", "appname", "attribute", "audience", "auth", "auth_header_name", "auth_method", "auth_path", "auth_role", "authenticated_userid", "aws_assume_role_arn", "aws_imds_protocol_version", "aws_key", "aws_region", "aws_role_session_name", "aws_secret", "awsgateway_compatible", "bandwidth_metrics", "base64_encode_body", "base_dn", "batch_flush_delay", "batch_span_count", "block_on_first_violation", "body", "body_filter", "ca_certificates", "cache_control", "cache_ttl", "cert", "cert_alt", "cert_details", "cert_digest", "cert_type", "certificate", "challenge", "challenge_method", "claims_to_verify", "client_certificate", "client_errors_severity", "client_id", "client_secret", "client_type", "clientid", "clock_skew", "code", "comment", "concurrency", "config", "config_hash", "connect_timeout", "consul", "consumer", "consumer_identifier_default", "consumer_tag", "content_type", "cookie_domain", "cookie_http_only", "cookie_name", "cookie_names", "cookie_path", "cookie_same_site", "cookie_secure", "created_at", "credential", "credentials", "custom_fields_by_lua", "custom_id", "data", "database", "day", "default_header_type", "default_service_name", "deny", "description", "destinations", "dictionary_name", "disable_https", "domains", "eab_hmac_key", "eab_kid", "echo", "echo_downstream", "enable_authorization_code", "enable_client_credentials", "enable_implicit_grant", "enable_ipv4_common_name", "enable_password_grant", "enabled", "endpoint", "enforce_headers", "entity_id", "entity_name", "error_code", "error_message", "expires", "expires_in", "expiry_timestamp", "exposed_headers", "facility", "fail_backoff_minutes", "fault_tolerant", "filters", "flush_timeout", "forward_request_body", "forward_request_headers", "forward_request_method", "forward_request_uri", "function_name", "functionname", "generator", "global_credentials", "group", "hash_fallback", "hash_fallback_header", "hash_fallback_query_arg", "hash_fallback_uri_capture", "hash_on", "hash_on_cookie", "hash_on_cookie_path", "hash_on_header", "hash_on_query_arg", "hash_on_uri_capture", "hash_secret", "header_filter", "header_name", "header_names", "header_type", "headers", "healthchecks", "healthy", "hide_client_headers", "hide_credentials", "hide_groups_header", "host", "host_header", "hostdomain", "hostname", "hostname_in_prefix", "hosts", "hour", "http_endpoint", "http_failures", "http_method", "http_path", "http_response_header_for_traceid", "http_span_name", "http_statuses", "https", "https_redirect_status_code", "https_sni", "https_verify", "https_verify_certificate", "id", "identifier", "idling_timeout", "ignore_uri_case", "include_credential", "initial_retry_delay", "instance_name", "interval", "invocation_type", "ip", "is_proxy_integration", "json", "json_types", "jwk", "jwt_path", "keepalive", "key", "key_alt", "key_claim_name", "key_id", "key_in_body", "key_in_header", "key_in_query", "key_names", "key_set", "kid", "kong", "kv_path", "labels", "last_seen", "latency_metrics", "ldap_host", "ldap_port", "ldaps", "limit_by", "limits", "local_service_name", "log", "log_level", "log_type", "logout_methods", "logout_post_arg", "logout_query_arg", "mandatory_scope", "max_age", "max_batch_size", "max_bytes", "max_coalescing_delay", "max_entries", "max_retry_delay", "max_retry_time", "maximum_expiration", "memory", "message", "meta", "method", "methods", "metrics", "minute", "month", "name", "namespace", "origins", "pass_stripped_path", "passive", "password", "path", "path_handling", "paths", "pem", "per_consumer", "period", "period_date", "phase_duration_flavor", "pkce", "plugin", "policy", "port", "preferred_chain", "prefix", "preflight_continue", "preserve_host", "private_key", "private_network", "proto", "protocol", "protocols", "provision_key", "proxy_url", "public_key", "qualifier", "querystring", "queue", "queue_size", "read_body_for_logout", "read_timeout", "redirect_uris", "redis", "redis_database", "redis_host", "redis_password", "redis_port", "redis_server_name", "redis_ssl", "redis_ssl_verify", "redis_timeout", "redis_username", "refresh_token", "refresh_token_ttl", "regex_priority", "remember", "remember_absolute_timeout", "remember_cookie_name", "remember_rolling_timeout", "remove", "rename", "renew_threshold_days", "reopen", "replace", "request_buffering", "request_headers", "request_method", "require_content_length", "resource_attributes", "response_buffering", "response_code", "response_headers", "retries", "retry_count", "reuse_refresh_token", "rewrite", "rolling_timeout", "route", "route_id", "routeprefix", "rsa_key_size", "rsa_public_key", "run_on_preflight", "sample_ratio", "scan_count", "scope", "scopes", "second", "secret", "secret_is_base64", "send_timeout", "server_errors_severity", "service", "service_id", "service_identifier_default", "service_name_tag", "session_id", "set", "shm", "shm_name", "size_unit", "skip_large_bodies", "slots", "snis", "sources", "ssl", "ssl_server_name", "ssl_verify", "stale_ttl", "start_tls", "static_tags", "status", "status_code", "status_code_metrics", "status_tag", "storage", "storage_config", "storage_ttl", "strategy", "strip_path", "successes", "successful_severity", "sync_rate", "sync_status", "tag", "tag_style", "tags", "tags_header", "target", "tcp_failures", "threshold", "timeout", "timeouts", "tls", "tls_server_name", "tls_sni", "tls_verify", "tls_verify_depth", "token", "token_expiration", "token_type", "tos_accepted", "traceid_byte_count", "trigger", "type", "udp_packet_size", "unhandled_status", "unhealthy", "updated_at", "upstream", "upstream_health_metrics", "uri", "uri_param_names", "use_srv_name", "use_tcp", "username", "validate_request_body", "value", "vary_headers", "vary_query_params", "vault", "verify_ldap_host", "version", "weight", "workspace_identifier_default", "write_timeout", "year" },
}


local buf_enc = buffer.new(options)
local buf_dec = buffer.new(options)


local _M = {}


function _M.marshall(value)
  if value == nil then
    return nil
  end

  value = buf_enc:reset():encode(value):get()

  return value
end


function _M.unmarshall(value, err)
  if value == nil or err then
    -- this allows error/nil propagation in deserializing value from LMDB
    return nil, err
  end

  value = buf_dec:set(value):decode()

  return value
end


return _M
