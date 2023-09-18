-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]


return {
  -- Any dataplane older than 3.1.0
  [3001000000] = {
    -- OSS
    acme = {
      "enable_ipv4_common_name",
      "storage_config.redis.ssl",
      "storage_config.redis.ssl_verify",
      "storage_config.redis.ssl_server_name",
    },
    rate_limiting = {
      "error_code",
      "error_message",
    },
    response_ratelimiting = {
      "redis_ssl",
      "redis_ssl_verify",
      "redis_server_name",
    },
    datadog = {
      "retry_count",
      "queue_size",
      "flush_timeout",
    },
    statsd = {
      "retry_count",
      "queue_size",
      "flush_timeout",
    },
    session = {
      "cookie_persistent",
    },
    zipkin = {
      "http_response_header_for_traceid",
    },

    -- Enterprise plugins
    mocking = {
      "included_status_codes",
      "random_status_code",
    },
    opa = {
      "include_uri_captures_in_opa_input",
    },
    forward_proxy = {
      "x_headers",
    },
    rate_limiting_advanced = {
      "disable_penalty",
      "error_code",
      "error_message",
    },
    mtls_auth = {
      "allow_partial_chain",
      "send_ca_dn",
    },
    request_transformer_advanced = {
      "dots_in_keys",
      "add.json_types",
      "append.json_types",
      "replace.json_types",
    },
    route_transformer_advanced = {
      "escape_path",
    },
  },

  -- Any dataplane older than 3.2.0
  [3002000000] = {
    -- OSS
    session = {
      "audience",
      "absolute_timeout",
      "remember_cookie_name",
      "remember_rolling_timeout",
      "remember_absolute_timeout",
      "response_headers",
      "request_headers",
    },
    statsd = {
      "tag_style",
    },
    -- Enterprise plugins
    openid_connect = {
      "session_audience",
      "session_remember",
      "session_remember_cookie_name",
      "session_remember_rolling_timeout",
      "session_remember_absolute_timeout",
      "session_absolute_timeout",
      "session_request_headers",
      "session_response_headers",
      "session_store_metadata",
      "session_enforce_same_subject",
      "session_hash_subject",
      "session_hash_storage_key",
    },
    saml = {
      "session_audience",
      "session_remember",
      "session_remember_cookie_name",
      "session_remember_rolling_timeout",
      "session_remember_absolute_timeout",
      "session_absolute_timeout",
      "session_request_headers",
      "session_response_headers",
      "session_store_metadata",
      "session_enforce_same_subject",
      "session_hash_subject",
      "session_hash_storage_key",
    },
    aws_lambda = {
      "aws_imds_protocol_version",
    },
    zipkin = {
      "phase_duration_flavor",
    }
  },

  -- Any dataplane older than 3.3.0
  [3003000000] = {
    acme = {
      "account_key",
      "storage_config.redis.namespace",
    },
    aws_lambda = {
      "disable_https",
    },
    proxy_cache = {
      "ignore_uri_case",
    },
    proxy_cache_advanced = {
      "ignore_uri_case",
    },
    opentelemetry = {
      "http_response_header_for_traceid",
      "queue",
      "header_type",
    },
    http_log = {
      "queue",
    },
    statsd = {
      "queue",
    },
    statsd_advanced = {
      "queue",
    },
    datadog = {
      "queue",
    },
    zipkin = {
      "queue",
    },
    jwt_signer = {
      "add_claims",
      "set_claims",
    },
  },

  -- Any dataplane older than 3.4.0
  [3004000000] = {
    -- Enterprise plugins
    openid_connect = {
      "expose_error_code",
      "token_cache_key_include_scope",
    },
    kafka_log = {
      "custom_fields_by_lua",
    },
    rate_limiting = {
      "sync_rate",
    },
    mocking = {
      "include_base_path",
    },
    oas_validation = {
      "include_base_path",
    },
    proxy_cache = {
      "response_headers",
    },
    proxy_cache_advanced = {
      "response_headers",
    },
  },

  -- Any dataplane older than 3.5.0
  [3005000000] = {
    cors = {
      "private_network",
    },
    -- Enterprise plugins
    openid_connect = {
      "using_pseudo_issuer",
      "unauthorized_destroy_session",
    },
  },

}
