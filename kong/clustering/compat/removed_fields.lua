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
    proxy_cache = {
      "response_headers",
    },
  },

  -- Any dataplane older than 3.4.0
  [3004003005] = {
    cors = {
      "private_network",
    },
  },

  -- Any dataplane older than 3.5.0
  [3005000000] = {
    acme = {
      "storage_config.redis.scan_count",
    },
    -- Enterprise plugins
    session = {
      "read_body_for_logout",
    },
    openid_connect = {
      "using_pseudo_issuer",
      "unauthorized_destroy_session",
      "introspection_token_param_name",
      "revocation_token_param_name",
      "proof_of_possession_mtls",
      "proof_of_possession_auth_methods_validation",
    },
    mocking = {
      "include_base_path",
    },
    oas_validation = {
      "include_base_path",
    },
    proxy_cache_advanced = {
      "response_headers",
    },
  },

  -- Any dataplane older than 3.6.0
  [3006000000] = {
    opentelemetry = {
      "sampling_rate",
    },
    basic_auth = {
      "realm"
    },
    -- Enterprise plugins
    openid_connect = {
      "tls_client_auth_cert_id",
      "tls_client_auth_ssl_verify",
      "mtls_token_endpoint",
      "mtls_introspection_endpoint",
      "mtls_revocation_endpoint",
      "pushed_authorization_request_endpoint",
      "pushed_authorization_request_endpoint_auth_method",
      "require_pushed_authorization_requests",
      "require_proof_key_for_code_exchange",
    },
    acl = {
      "include_consumer_groups"
    }
  },

  -- Any dataplane older than 3.7.0
  [3007000000] = {
    key_auth = {
      "realm"
    },
    -- Enterprise plugins
    oas_validation = {
      "custom_base_path",
    },
    mocking = {
      "custom_base_path",
    },
    jwt_signer = {
      "add_access_token_claims",
      "add_channel_token_claims",
      "set_access_token_claims",
      "set_channel_token_claims",
      "remove_access_token_claims",
      "remove_channel_token_claims",
      "original_access_token_upstream_header",
      "original_channel_token_upstream_header",
      "access_token_jwks_uri_client_username",
      "access_token_jwks_uri_client_password",
      "access_token_jwks_uri_client_certificate",
      "access_token_jwks_uri_rotate_period",
      "access_token_keyset_client_username",
      "access_token_keyset_client_password",
      "access_token_keyset_client_certificate",
      "access_token_keyset_rotate_period",
      "channel_token_jwks_uri_client_username",
      "channel_token_jwks_uri_client_password",
      "channel_token_jwks_uri_client_certificate",
      "channel_token_jwks_uri_rotate_period",
      "channel_token_keyset_client_username",
      "channel_token_keyset_client_password",
      "channel_token_keyset_client_certificate",
      "channel_token_keyset_rotate_period",
    },
    opentelemetry = {
      "propagation",
    },
    zipkin = {
      "propagation",
    },
    graphql_proxy_cache_advanced = {
      "redis",
      "bypass_on_err",
    },
    openid_connect = {
      "require_signed_request_object",
      "proof_of_possession_dpop",
      "dpop_use_nonce",
      "dpop_proof_lifetime",
    },
    ai_proxy = {
      "response_streaming",
      "model.options.upstream_path",
      "auth.azure_use_managed_identity",
      "auth.azure_client_id",
      "auth.azure_client_secret",
      "auth.azure_tenant_id",
    },
    ai_request_transformer = {
      "llm.model.options.upstream_path",
      "llm.auth.azure_use_managed_identity",
      "llm.auth.azure_client_id",
      "llm.auth.azure_client_secret",
      "llm.auth.azure_tenant_id",
    },
    ai_response_transformer = {
      "llm.model.options.upstream_path",
      "llm.auth.azure_use_managed_identity",
      "llm.auth.azure_client_id",
      "llm.auth.azure_client_secret",
      "llm.auth.azure_tenant_id",
    }
  },

  -- Any dataplane older than 3.8.0
  [3008000000] = {
    ldap_auth = {
      "realm",
    },
    hmac_auth = {
      "realm",
    },
    jwt = {
      "realm",
    },
    oauth2 = {
      "realm",
    },
    opentelemetry = {
      "traces_endpoint",
      "logs_endpoint",
      "queue.concurrency_limit",
    },
    response_transformer = {
      "rename.json",
    },
    ai_proxy = {
      "max_request_body_size",
      "model.options.gemini",
      "auth.gcp_use_service_account",
      "auth.gcp_service_account_json",
      "model.options.bedrock",
      "auth.aws_access_key_id",
      "auth.aws_secret_access_key",
      "auth.allow_override",
      "model_name_header",
    },
    ai_prompt_decorator = {
      "max_request_body_size",
    },
    ai_prompt_guard = {
      "max_request_body_size",
      "match_all_roles",
    },
    ai_prompt_template = {
      "max_request_body_size",
    },
    ai_request_transformer = {
      "max_request_body_size",
      "llm.model.options.gemini",
      "llm.auth.gcp_use_service_account",
      "llm.auth.gcp_service_account_json",
      "llm.model.options.bedrock",
      "llm.auth.aws_access_key_id",
      "llm.auth.aws_secret_access_key",
      "llm.auth.allow_override",
    },
    ai_response_transformer = {
      "max_request_body_size",
      "llm.model.options.gemini",
      "llm.auth.gcp_use_service_account",
      "llm.auth.gcp_service_account_json",
      "llm.model.options.bedrock",
      "llm.auth.aws_access_key_id",
      "llm.auth.aws_secret_access_key",
      "llm.auth.allow_override",
    },
    -- Enterprise plugins
    openid_connect = {
      "claims_forbidden",
      "cluster_cache_strategy",
      "cluster_cache_redis",
      "redis"
    },
    proxy_cache_advanced = {
      "redis.cluster_max_redirections",
      "redis.cluster_nodes",
      "redis.sentinel_nodes",
    },
    graphql_proxy_cache_advanced = {
      "redis.cluster_max_redirections",
      "redis.cluster_nodes",
      "redis.sentinel_nodes",
    },
    graphql_rate_limiting_advanced = {
      "redis.cluster_max_redirections",
      "redis.cluster_nodes",
      "redis.sentinel_nodes",
    },
    rate_limiting_advanced = {
      "redis.cluster_max_redirections",
      "redis.cluster_nodes",
      "redis.sentinel_nodes",
    },
    saml = {
      "redis",
    },
    ai_rate_limiting_advanced = {
      "redis.cluster_max_redirections",
      "redis.cluster_nodes",
      "redis.sentinel_nodes",
    },
    key_auth_enc = {
      "realm",
    },
    ldap_auth_advanced = {
      "realm",
    },
    prometheus = {
      "ai_metrics",
    },
    json_threat_protection = {
      "max_body_size",
      "max_container_depth",
      "max_object_entry_count",
      "max_object_entry_name_length",
      "max_array_element_count",
      "max_string_value_length",
      "enforcement_mode",
      "error_status_code",
      "error_message",
    },
    acl = {
      "always_use_authenticated_groups",
    },
    http_log = {
      "queue.concurrency_limit",
    },
    statsd = {
      "queue.concurrency_limit",
    },
    datadog = {
      "queue.concurrency_limit",
    },
    zipkin = {
      "queue.concurrency_limit",
    },
    statsd_advanced = {
      "queue.concurrency_limit",
    },
  },

  -- Any dataplane older than 3.9.0
  [3009000000] = {
    -- Enterprise plugins
    rate_limiting_advanced = {
      "lock_dictionary_name",
      "redis.redis_proxy_type",
      "compound_identifier",
    },
    ai_semantic_cache = {
      "ignore_tool_prompts"
    },
    ai_proxy_advanced = {
      "response_streaming",
    },
    openid_connect = {
      "introspection_post_args_client_headers",
    },
  },
}
