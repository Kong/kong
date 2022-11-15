-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

_G.kong = {
  -- XXX EE: kong.version is used in some warning messages in
  -- clustering/control_plane.lua and fail if nil
  version = "x.y.z",
  configuration = {
      cluster_max_payload = 4194304
    }
}

local cp = require("kong.clustering.control_plane")
local cjson_decode = require("cjson").decode
local inflate_gzip = require("kong.tools.utils").inflate_gzip

describe("kong.clustering.control_plane", function()
  it("calculating version_num", function()
    assert.equal(2003004000, cp._version_num("2.3.4"))
    assert.equal(2003004000, cp._version_num("2.3.4-rc1"))
    assert.equal(2003004000, cp._version_num("2.3.4beta2"))
    assert.equal(2003004001, cp._version_num("2.3.4.1"))
    assert.equal(2003004001, cp._version_num("2.3.4.1-rc1"))
    assert.equal(2003004001, cp._version_num("2.3.4.1beta2"))
    assert.equal(2007000000, cp._version_num("2.7.0.0"))
    assert.equal(2007000001, cp._version_num("2.7.0.1"))
    assert.equal(2008000000, cp._version_num("2.8.0.0"))
    assert.equal(2008001000, cp._version_num("2.8.1.0"))
    assert.equal(2008001001, cp._version_num("2.8.1.1"))
    assert.equal(2008001002, cp._version_num("2.8.1.2"))
    assert.equal(2008001003, cp._version_num("2.8.1.3"))
    assert.equal(3001000000, cp._version_num("3.1.0.0"))
  end)


  it("merging get_removed_fields", function()
    assert.same({
      file_log = {
        "custom_fields_by_lua",
      },
      http_log = {
        "custom_fields_by_lua",
      },
      loggly = {
        "custom_fields_by_lua",
      },
      prometheus = {
        "status_code_metrics",
        "latency_metrics",
        "bandwidth_metrics",
        "upstream_health_metrics",
        "per_consumer",
      },
      syslog = {
        "facility",
        "custom_fields_by_lua",
      },
      tcp_log = {
        "custom_fields_by_lua",
      },
      udp_log = {
        "custom_fields_by_lua",
      },
      zipkin = {
        "http_span_name",
        "connect_timeout",
        "send_timeout",
        "read_timeout",
        "tags_header",
        "local_service_name",
      },
      redis = {
        "connect_timeout",
        "keepalive_backlog",
        "read_timeout",
        "send_timeout",
        "keepalive_pool_size",
        "username",
        "sentinel_username",
      },
      acme = {
        "preferred_chain",
        "rsa_key_size",
        "allow_any_domain",
      },
      aws_lambda = {
        "base64_encode_body",
        "aws_assume_role_arn",
        "aws_role_session_name",
      },
      grpc_web = {
        "allow_origin_header",
      },
      request_termination = {
        "echo",
        "trigger",
      },
      canary = {
        "hash_header",
        "canary_by_header_name",
      },
      kafka_log = {
        "authentication",
        "keepalive_enabled",
        "security",
        "cluster_name",
      },
      kafka_upstream = {
        "authentication",
        "keepalive_enabled",
        "security",
        "cluster_name",
      },
      openid_connect = {
        "by_username_ignore_case",
        "disable_session",
        "downstream_introspection_jwt_header",
        "downstream_user_info_jwt_header",
        "introspection_accept",
        "introspection_check_active",
        "upstream_introspection_jwt_header",
        "upstream_user_info_jwt_header",
        "userinfo_accept",
        "userinfo_headers_client",
        "userinfo_headers_names",
        "userinfo_headers_values",
        "userinfo_query_args_client",
        "userinfo_query_args_names",
        "userinfo_query_args_values",
        "session_redis_username",
        "resolve_distributed_claims",
        auth_methods = {
          "userinfo",
        },
        ignore_signature = {
          "introspection",
          "userinfo",
        },
        login_methods = {
          "userinfo",
        },
        token_headers_grants = {
          "refresh_token",
        },
      },
      rate_limiting_advanced = {
        "path",
        "disable_penalty",
        "enforce_consumer_groups",
        "consumer_groups",
      },
      forward_proxy = {
        "x_headers",
        "https_proxy_host",
        "https_proxy_port",
        "auth_username",
        "auth_password",
      },
      mocking = {
        "random_examples",
      },
      datadog = {
        "service_name_tag",
        "status_tag",
        "consumer_tag",
      },
      ip_restriction = {
        "status",
        "message",
      },
      rate_limiting = {
        "error_code",
        "error_message",
        "redis_username",
        "redis_ssl",
        "redis_ssl_verify",
        "redis_server_name",
      },
      response_ratelimiting = {
        "redis_username",
      },
      opa = {
        "include_uri_captures_in_opa_input",
        "include_body_in_opa_input",
        "include_parsed_json_body_in_opa_input",
        "ssl_verify",
      },
      degraphql = {
        "graphql_server_path",
      },
      opentelemetry = {
        "connect_timeout",
        "send_timeout",
        "read_timeout",
      },
      pre_function = {
        "ws_handshake",
        "ws_client_frame",
        "ws_upstream_frame",
        "ws_close",
      },
      post_function = {
        "ws_handshake",
        "ws_client_frame",
        "ws_upstream_frame",
        "ws_close",
      },
      mtls_auth = {
        "allow_partial_chain",
        "http_proxy_host",
        "http_proxy_port",
        "https_proxy_host",
        "https_proxy_port",
      },
      statsd_advanced = {
        "consumer_identifier_default",
        "service_identifier_default",
        "workspace_identifier_default",
      },
      statsd = {
        "allow_status_codes",
        "udp_packet_size",
        "use_tcp",
        "hostname_in_prefix",
        "consumer_identifier_default",
        "service_identifier_default",
        "workspace_identifier_default",
      },
      ldap_auth_advanced = {
        "groups_required"
      },
      request_transformer_advanced = {
        "dots_in_keys",
        replace = { "json_types", },
        add = { "json_types", },
        append = { "json_types", },
      },
    }, cp._get_removed_fields(2003000000))

    assert.same({
      redis = {
        "connect_timeout",
        "keepalive_backlog",
        "read_timeout",
        "send_timeout",
        "keepalive_pool_size",
        "username",
        "sentinel_username",
      },
      prometheus = {
        "status_code_metrics",
        "latency_metrics",
        "bandwidth_metrics",
        "upstream_health_metrics",
        "per_consumer",
      },
      zipkin = {
        "http_span_name",
        "connect_timeout",
        "send_timeout",
        "read_timeout",
        "tags_header",
        "local_service_name",
      },
      syslog = {
        "facility",
      },
      acme = {
        "preferred_chain",
        "rsa_key_size",
        "allow_any_domain",
      },
      aws_lambda = {
        "base64_encode_body",
        "aws_assume_role_arn",
        "aws_role_session_name",
      },
      grpc_web = {
        "allow_origin_header",
      },
      request_termination = {
        "echo",
        "trigger",
      },
      canary = {
        "hash_header",
        "canary_by_header_name",
      },
      kafka_log = {
        "authentication",
        "keepalive_enabled",
        "security",
        "cluster_name",
      },
      kafka_upstream = {
        "authentication",
        "keepalive_enabled",
        "security",
        "cluster_name",
      },
      openid_connect = {
        "by_username_ignore_case",
        "disable_session",
        "downstream_introspection_jwt_header",
        "downstream_user_info_jwt_header",
        "introspection_accept",
        "introspection_check_active",
        "upstream_introspection_jwt_header",
        "upstream_user_info_jwt_header",
        "userinfo_accept",
        "userinfo_headers_client",
        "userinfo_headers_names",
        "userinfo_headers_values",
        "userinfo_query_args_client",
        "userinfo_query_args_names",
        "userinfo_query_args_values",
        "session_redis_username",
        "resolve_distributed_claims",
        auth_methods = {
          "userinfo",
        },
        ignore_signature = {
          "introspection",
          "userinfo",
        },
        login_methods = {
          "userinfo",
        },
        token_headers_grants = {
          "refresh_token",
        },
      },
      rate_limiting_advanced = {
        "path",
        "disable_penalty",
        "enforce_consumer_groups",
        "consumer_groups",
      },
      forward_proxy = {
        "x_headers",
        "https_proxy_host",
        "https_proxy_port",
        "auth_username",
        "auth_password",
      },
      mocking = {
        "random_examples",
      },
      datadog = {
        "service_name_tag",
        "status_tag",
        "consumer_tag",
      },
      ip_restriction = {
        "status",
        "message",
      },
      rate_limiting = {
        "error_code",
        "error_message",
        "redis_username",
        "redis_ssl",
        "redis_ssl_verify",
        "redis_server_name",
      },
      response_ratelimiting = {
        "redis_username",
      },
      opa = {
        "include_uri_captures_in_opa_input",
        "include_body_in_opa_input",
        "include_parsed_json_body_in_opa_input",
        "ssl_verify",
      },
      degraphql = {
        "graphql_server_path",
      },
      opentelemetry = {
        "connect_timeout",
        "send_timeout",
        "read_timeout",
      },
      pre_function = {
        "ws_handshake",
        "ws_client_frame",
        "ws_upstream_frame",
        "ws_close",
      },
      post_function = {
        "ws_handshake",
        "ws_client_frame",
        "ws_upstream_frame",
        "ws_close",
      },
      mtls_auth = {
        "allow_partial_chain",
        "http_proxy_host",
        "http_proxy_port",
        "https_proxy_host",
        "https_proxy_port",
      },
      statsd_advanced = {
        "consumer_identifier_default",
        "service_identifier_default",
        "workspace_identifier_default",
      },
      statsd = {
        "allow_status_codes",
        "udp_packet_size",
        "use_tcp",
        "hostname_in_prefix",
        "consumer_identifier_default",
        "service_identifier_default",
        "workspace_identifier_default",
      },
      ldap_auth_advanced = {
        "groups_required"
      },
      request_transformer_advanced = {
        "dots_in_keys",
        replace = { "json_types", },
        add = { "json_types", },
        append = { "json_types", },
      },
    }, cp._get_removed_fields(2003003003))

    assert.same({
      redis = {
        "connect_timeout",
        "keepalive_backlog",
        "read_timeout",
        "send_timeout",
        "keepalive_pool_size",
        "username",
        "sentinel_username",
      },
      syslog = {
        "facility",
      },
      prometheus = {
        "status_code_metrics",
        "latency_metrics",
        "bandwidth_metrics",
        "upstream_health_metrics",
        "per_consumer",
      },
      zipkin = {
        "http_span_name",
        "connect_timeout",
        "send_timeout",
        "read_timeout",
        "tags_header",
        "local_service_name",
      },
      acme = {
        "preferred_chain",
        "rsa_key_size",
        "allow_any_domain",
      },
      aws_lambda = {
        "base64_encode_body",
        "aws_assume_role_arn",
        "aws_role_session_name",
      },
      grpc_web = {
        "allow_origin_header",
      },
      request_termination = {
        "echo",
        "trigger",
      },
      canary = {
        "hash_header",
        "canary_by_header_name",
      },
      kafka_log = {
        "authentication",
        "keepalive_enabled",
        "security",
        "cluster_name",
      },
      kafka_upstream = {
        "authentication",
        "keepalive_enabled",
        "security",
        "cluster_name",
      },
      openid_connect = {
        "by_username_ignore_case",
        "disable_session",
        "downstream_introspection_jwt_header",
        "downstream_user_info_jwt_header",
        "introspection_accept",
        "introspection_check_active",
        "upstream_introspection_jwt_header",
        "upstream_user_info_jwt_header",
        "userinfo_accept",
        "userinfo_headers_client",
        "userinfo_headers_names",
        "userinfo_headers_values",
        "userinfo_query_args_client",
        "userinfo_query_args_names",
        "userinfo_query_args_values",
        "session_redis_username",
        "resolve_distributed_claims",
        auth_methods = {
          "userinfo",
        },
        ignore_signature = {
          "introspection",
          "userinfo",
        },
        login_methods = {
          "userinfo",
        },
        token_headers_grants = {
          "refresh_token",
        },
      },
      rate_limiting_advanced = {
        "path",
        "disable_penalty",
        "enforce_consumer_groups",
        "consumer_groups",
      },
      forward_proxy = {
        "x_headers",
        "https_proxy_host",
        "https_proxy_port",
        "auth_username",
        "auth_password",
      },
      mocking = {
        "random_examples",
      },
      datadog = {
        "service_name_tag",
        "status_tag",
        "consumer_tag",
      },
      ip_restriction = {
        "status",
        "message",
      },
      rate_limiting = {
        "error_code",
        "error_message",
        "redis_username",
        "redis_ssl",
        "redis_ssl_verify",
        "redis_server_name",
      },
      response_ratelimiting = {
        "redis_username",
      },
      opa = {
        "include_uri_captures_in_opa_input",
        "include_body_in_opa_input",
        "include_parsed_json_body_in_opa_input",
        "ssl_verify",
      },
      degraphql = {
        "graphql_server_path",
      },
      opentelemetry = {
        "connect_timeout",
        "send_timeout",
        "read_timeout",
      },
      pre_function = {
        "ws_handshake",
        "ws_client_frame",
        "ws_upstream_frame",
        "ws_close",
      },
      post_function = {
        "ws_handshake",
        "ws_client_frame",
        "ws_upstream_frame",
        "ws_close",
      },
      mtls_auth = {
        "allow_partial_chain",
        "http_proxy_host",
        "http_proxy_port",
        "https_proxy_host",
        "https_proxy_port",
      },
      statsd_advanced = {
        "consumer_identifier_default",
        "service_identifier_default",
        "workspace_identifier_default",
      },
      statsd = {
        "allow_status_codes",
        "udp_packet_size",
        "use_tcp",
        "hostname_in_prefix",
        "consumer_identifier_default",
        "service_identifier_default",
        "workspace_identifier_default",
      },
      ldap_auth_advanced = {
        "groups_required"
      },
      request_transformer_advanced = {
        "dots_in_keys",
        replace = { "json_types", },
        add = { "json_types", },
        append = { "json_types", },
      },
    }, cp._get_removed_fields(2003004000))

    assert.same({
      redis = {
        "connect_timeout",
        "keepalive_backlog",
        "read_timeout",
        "send_timeout",
        "keepalive_pool_size",
        "username",
        "sentinel_username",
      },
      syslog = {
        "facility",
      },
      acme = {
        "preferred_chain",
        "rsa_key_size",
        "allow_any_domain",
      },
      aws_lambda = {
        "base64_encode_body",
        "aws_assume_role_arn",
        "aws_role_session_name",
      },
      grpc_web = {
        "allow_origin_header",
      },
      request_termination = {
        "echo",
        "trigger",
      },
      canary = {
        "hash_header",
        "canary_by_header_name",
      },
      kafka_log = {
        "authentication",
        "keepalive_enabled",
        "security",
        "cluster_name",
      },
      kafka_upstream = {
        "authentication",
        "keepalive_enabled",
        "security",
        "cluster_name",
      },
      openid_connect = {
        "by_username_ignore_case",
        "disable_session",
        "downstream_introspection_jwt_header",
        "downstream_user_info_jwt_header",
        "introspection_accept",
        "introspection_check_active",
        "upstream_introspection_jwt_header",
        "upstream_user_info_jwt_header",
        "userinfo_accept",
        "userinfo_headers_client",
        "userinfo_headers_names",
        "userinfo_headers_values",
        "userinfo_query_args_client",
        "userinfo_query_args_names",
        "userinfo_query_args_values",
        "session_redis_username",
        "resolve_distributed_claims",
        auth_methods = {
          "userinfo",
        },
        ignore_signature = {
          "introspection",
          "userinfo",
        },
        login_methods = {
          "userinfo",
        },
        token_headers_grants = {
          "refresh_token",
        },
      },
      rate_limiting_advanced = {
        "path",
        "disable_penalty",
        "enforce_consumer_groups",
        "consumer_groups",
      },
      forward_proxy = {
        "x_headers",
        "https_proxy_host",
        "https_proxy_port",
        "auth_username",
        "auth_password",
      },
      mocking = {
        "random_examples",
      },
      datadog = {
        "service_name_tag",
        "status_tag",
        "consumer_tag",
      },
      ip_restriction = {
        "status",
        "message",
      },
      rate_limiting = {
        "error_code",
        "error_message",
        "redis_username",
        "redis_ssl",
        "redis_ssl_verify",
        "redis_server_name",
      },
      zipkin = {
        "http_span_name",
        "connect_timeout",
        "send_timeout",
        "read_timeout",
        "local_service_name",
      },
      response_ratelimiting = {
        "redis_username",
      },
      opa = {
        "include_uri_captures_in_opa_input",
        "include_body_in_opa_input",
        "include_parsed_json_body_in_opa_input",
        "ssl_verify",
      },
      degraphql = {
        "graphql_server_path",
      },
      opentelemetry = {
        "connect_timeout",
        "send_timeout",
        "read_timeout",
      },
      prometheus = {
        "status_code_metrics",
        "latency_metrics",
        "bandwidth_metrics",
        "upstream_health_metrics",
      },
      pre_function = {
        "ws_handshake",
        "ws_client_frame",
        "ws_upstream_frame",
        "ws_close",
      },
      post_function = {
        "ws_handshake",
        "ws_client_frame",
        "ws_upstream_frame",
        "ws_close",
      },
      mtls_auth = {
        "allow_partial_chain",
        "http_proxy_host",
        "http_proxy_port",
        "https_proxy_host",
        "https_proxy_port",
      },
      statsd_advanced = {
        "consumer_identifier_default",
        "service_identifier_default",
        "workspace_identifier_default",
      },
      statsd = {
        "allow_status_codes",
        "udp_packet_size",
        "use_tcp",
        "hostname_in_prefix",
        "consumer_identifier_default",
        "service_identifier_default",
        "workspace_identifier_default",
      },
      ldap_auth_advanced = {
        "groups_required"
      },
      request_transformer_advanced = {
        "dots_in_keys",
        replace = { "json_types", },
        add = { "json_types", },
        append = { "json_types", },
      },
    }, cp._get_removed_fields(2004001000))

    assert.same({
      redis = {
        "keepalive_pool_size",
        "username",
        "sentinel_username",
      },
      acme = {
        "preferred_chain",
        "rsa_key_size",
        "allow_any_domain",
      },
      aws_lambda = {
        "base64_encode_body",
        "aws_assume_role_arn",
        "aws_role_session_name",
      },
      grpc_web = {
        "allow_origin_header",
      },
      request_termination = {
        "echo",
        "trigger",
      },
      canary = {
        "hash_header",
        "canary_by_header_name",
      },
      kafka_log = {
        "authentication",
        "keepalive_enabled",
        "security",
        "cluster_name",
      },
      kafka_upstream = {
        "authentication",
        "keepalive_enabled",
        "security",
        "cluster_name",
      },
      openid_connect = {
        "by_username_ignore_case",
        "disable_session",
        "downstream_introspection_jwt_header",
        "downstream_user_info_jwt_header",
        "introspection_accept",
        "introspection_check_active",
        "upstream_introspection_jwt_header",
        "upstream_user_info_jwt_header",
        "userinfo_accept",
        "userinfo_headers_client",
        "userinfo_headers_names",
        "userinfo_headers_values",
        "userinfo_query_args_client",
        "userinfo_query_args_names",
        "userinfo_query_args_values",
        "session_redis_username",
        "resolve_distributed_claims",
        auth_methods = {
          "userinfo",
        },
        ignore_signature = {
          "introspection",
          "userinfo",
        },
        login_methods = {
          "userinfo",
        },
        token_headers_grants = {
          "refresh_token",
        },
      },
      rate_limiting_advanced = {
        "path",
        "disable_penalty",
        "enforce_consumer_groups",
        "consumer_groups",
      },
      forward_proxy = {
        "x_headers",
        "https_proxy_host",
        "https_proxy_port",
        "auth_username",
        "auth_password",
      },
      mocking = {
        "random_examples",
      },
      datadog = {
        "service_name_tag",
        "status_tag",
        "consumer_tag",
      },
      ip_restriction = {
        "status",
        "message",
      },
      rate_limiting = {
        "error_code",
        "error_message",
        "redis_username",
        "redis_ssl",
        "redis_ssl_verify",
        "redis_server_name",
      },
      zipkin = {
        "http_span_name",
        "connect_timeout",
        "send_timeout",
        "read_timeout",
        "local_service_name",
      },
      response_ratelimiting = {
        "redis_username",
      },
      opa = {
        "include_uri_captures_in_opa_input",
        "include_body_in_opa_input",
        "include_parsed_json_body_in_opa_input",
        "ssl_verify",
      },
      degraphql = {
        "graphql_server_path",
      },
      opentelemetry = {
        "connect_timeout",
        "send_timeout",
        "read_timeout",
      },
      prometheus = {
        "status_code_metrics",
        "latency_metrics",
        "bandwidth_metrics",
        "upstream_health_metrics",
      },
      pre_function = {
        "ws_handshake",
        "ws_client_frame",
        "ws_upstream_frame",
        "ws_close",
      },
      post_function = {
        "ws_handshake",
        "ws_client_frame",
        "ws_upstream_frame",
        "ws_close",
      },
      mtls_auth = {
        "allow_partial_chain",
        "http_proxy_host",
        "http_proxy_port",
        "https_proxy_host",
        "https_proxy_port",
      },
      statsd_advanced = {
        "consumer_identifier_default",
        "service_identifier_default",
        "workspace_identifier_default",
      },
      statsd = {
        "allow_status_codes",
        "udp_packet_size",
        "use_tcp",
        "hostname_in_prefix",
        "consumer_identifier_default",
        "service_identifier_default",
        "workspace_identifier_default",
      },
      ldap_auth_advanced = {
        "groups_required"
      },
      request_transformer_advanced = {
        "dots_in_keys",
        replace = { "json_types", },
        add = { "json_types", },
        append = { "json_types", },
      },
    }, cp._get_removed_fields(2004001002))

    assert.same({
      acme = {
        "preferred_chain",
        "rsa_key_size",
        "allow_any_domain",
      },
      aws_lambda = {
        "base64_encode_body",
        "aws_assume_role_arn",
        "aws_role_session_name",
      },
      grpc_web = {
        "allow_origin_header",
      },
      request_termination = {
        "echo",
        "trigger",
      },
      canary = {
        "hash_header",
        "canary_by_header_name",
      },
      kafka_log = {
        "authentication",
        "keepalive_enabled",
        "security",
        "cluster_name",
      },
      kafka_upstream = {
        "authentication",
        "keepalive_enabled",
        "security",
        "cluster_name",
      },
      openid_connect = {
        "by_username_ignore_case",
        "disable_session",
        "downstream_introspection_jwt_header",
        "downstream_user_info_jwt_header",
        "introspection_accept",
        "introspection_check_active",
        "upstream_introspection_jwt_header",
        "upstream_user_info_jwt_header",
        "userinfo_accept",
        "userinfo_headers_client",
        "userinfo_headers_names",
        "userinfo_headers_values",
        "userinfo_query_args_client",
        "userinfo_query_args_names",
        "userinfo_query_args_values",
        "session_redis_username",
        "resolve_distributed_claims",
        auth_methods = {
          "userinfo",
        },
        ignore_signature = {
          "introspection",
          "userinfo",
        },
        login_methods = {
          "userinfo",
        },
        token_headers_grants = {
          "refresh_token",
        },
      },
      rate_limiting_advanced = {
        "path",
        "disable_penalty",
        "enforce_consumer_groups",
        "consumer_groups",
      },
      forward_proxy = {
        "x_headers",
        "https_proxy_host",
        "https_proxy_port",
        "auth_username",
        "auth_password",
      },
      mocking = {
        "random_examples",
      },
      datadog = {
        "service_name_tag",
        "status_tag",
        "consumer_tag",
      },
      ip_restriction = {
        "status",
        "message",
      },
      rate_limiting = {
        "error_code",
        "error_message",
        "redis_username",
        "redis_ssl",
        "redis_ssl_verify",
        "redis_server_name",
      },
      zipkin = {
        "http_span_name",
        "connect_timeout",
        "send_timeout",
        "read_timeout",
        "local_service_name",
      },
      redis = {
        "username",
        "sentinel_username",
      },
      response_ratelimiting = {
        "redis_username",
      },
      opa = {
        "include_uri_captures_in_opa_input",
        "include_body_in_opa_input",
        "include_parsed_json_body_in_opa_input",
        "ssl_verify",
      },
      degraphql = {
        "graphql_server_path",
      },
      opentelemetry = {
        "connect_timeout",
        "send_timeout",
        "read_timeout",
      },
      prometheus = {
        "status_code_metrics",
        "latency_metrics",
        "bandwidth_metrics",
        "upstream_health_metrics",
      },
      pre_function = {
        "ws_handshake",
        "ws_client_frame",
        "ws_upstream_frame",
        "ws_close",
      },
      post_function = {
        "ws_handshake",
        "ws_client_frame",
        "ws_upstream_frame",
        "ws_close",
      },
      mtls_auth = {
        "allow_partial_chain",
        "http_proxy_host",
        "http_proxy_port",
        "https_proxy_host",
        "https_proxy_port",
      },
      statsd_advanced = {
        "consumer_identifier_default",
        "service_identifier_default",
        "workspace_identifier_default",
      },
      statsd = {
        "allow_status_codes",
        "udp_packet_size",
        "use_tcp",
        "hostname_in_prefix",
        "consumer_identifier_default",
        "service_identifier_default",
        "workspace_identifier_default",
      },
      ldap_auth_advanced = {
        "groups_required"
      },
      request_transformer_advanced = {
        "dots_in_keys",
        replace = { "json_types", },
        add = { "json_types", },
        append = { "json_types", },
      },
    }, cp._get_removed_fields(2005000000))

    assert.same({
      acme = {
        "rsa_key_size",
        "allow_any_domain",
      },
      aws_lambda = {
        "aws_assume_role_arn",
        "aws_role_session_name",
      },
      canary = {
        "canary_by_header_name",
      },
      forward_proxy = {
        "x_headers",
        "https_proxy_host",
        "https_proxy_port",
        "auth_username",
        "auth_password",
      },
      mocking = {
        "random_examples",
      },
      rate_limiting_advanced = {
        "disable_penalty",
        "enforce_consumer_groups",
        "consumer_groups",
      },
      datadog = {
        "service_name_tag",
        "status_tag",
        "consumer_tag",
      },
      ip_restriction = {
        "status",
        "message",
      },
      rate_limiting = {
        "error_code",
        "error_message",
        "redis_username",
        "redis_ssl",
        "redis_ssl_verify",
        "redis_server_name",
      },
      zipkin = {
        "http_span_name",
        "connect_timeout",
        "send_timeout",
        "read_timeout",
        "local_service_name",
      },
      openid_connect = {
        "session_redis_username",
        "resolve_distributed_claims",
      },
      redis = {
        "username",
        "sentinel_username",
      },
      kafka_log = {
        "cluster_name",
      },
      kafka_upstream = {
        "cluster_name",
      },
      response_ratelimiting = {
        "redis_username",
      },
      opa = {
        "include_uri_captures_in_opa_input",
        "include_body_in_opa_input",
        "include_parsed_json_body_in_opa_input",
        "ssl_verify",
      },
      degraphql = {
        "graphql_server_path",
      },
      opentelemetry = {
        "connect_timeout",
        "send_timeout",
        "read_timeout",
      },
      prometheus = {
        "status_code_metrics",
        "latency_metrics",
        "bandwidth_metrics",
        "upstream_health_metrics",
      },
      pre_function = {
        "ws_handshake",
        "ws_client_frame",
        "ws_upstream_frame",
        "ws_close",
      },
      post_function = {
        "ws_handshake",
        "ws_client_frame",
        "ws_upstream_frame",
        "ws_close",
      },
      mtls_auth = {
        "allow_partial_chain",
        "http_proxy_host",
        "http_proxy_port",
        "https_proxy_host",
        "https_proxy_port",
      },
      statsd_advanced = {
        "consumer_identifier_default",
        "service_identifier_default",
        "workspace_identifier_default",
      },
      statsd = {
        "allow_status_codes",
        "udp_packet_size",
        "use_tcp",
        "hostname_in_prefix",
        "consumer_identifier_default",
        "service_identifier_default",
        "workspace_identifier_default",
      },
      ldap_auth_advanced = {
        "groups_required"
      },
      request_transformer_advanced = {
        "dots_in_keys",
        replace = { "json_types", },
        add = { "json_types", },
        append = { "json_types", },
      },
    }, cp._get_removed_fields(2006000000))

    assert.same({
      acme = {
        "rsa_key_size",
        "allow_any_domain",
      },
      aws_lambda = {
        "aws_assume_role_arn",
        "aws_role_session_name",
      },
      canary = {
        "canary_by_header_name",
      },
      forward_proxy = {
        "x_headers",
        "https_proxy_host",
        "https_proxy_port",
      },
      openid_connect = {
        "session_redis_username",
        "resolve_distributed_claims",
      },
      redis = {
        "username",
        "sentinel_username",
      },
      kafka_log = {
        "cluster_name",
      },
      kafka_upstream = {
        "cluster_name",
      },
      response_ratelimiting = {
        "redis_username",
      },
      zipkin = {
        "http_span_name",
        "connect_timeout",
        "send_timeout",
        "read_timeout",
      },
      opa = {
        "include_uri_captures_in_opa_input",
        "include_body_in_opa_input",
        "include_parsed_json_body_in_opa_input",
        "ssl_verify",
      },
      degraphql = {
        "graphql_server_path",
      },
      opentelemetry = {
        "connect_timeout",
        "send_timeout",
        "read_timeout",
      },
      prometheus = {
        "status_code_metrics",
        "latency_metrics",
        "bandwidth_metrics",
        "upstream_health_metrics",
      },
      pre_function = {
        "ws_handshake",
        "ws_client_frame",
        "ws_upstream_frame",
        "ws_close",
      },
      post_function = {
        "ws_handshake",
        "ws_client_frame",
        "ws_upstream_frame",
        "ws_close",
      },
      mtls_auth = {
        "allow_partial_chain",
        "http_proxy_host",
        "http_proxy_port",
        "https_proxy_host",
        "https_proxy_port",
      },
      statsd_advanced = {
        "consumer_identifier_default",
        "service_identifier_default",
        "workspace_identifier_default",
      },
      statsd = {
        "allow_status_codes",
        "udp_packet_size",
        "use_tcp",
        "hostname_in_prefix",
        "consumer_identifier_default",
        "service_identifier_default",
        "workspace_identifier_default",
      },
      ldap_auth_advanced = {
        "groups_required"
      },
      rate_limiting_advanced = {
        "disable_penalty",
      },
      rate_limiting = {
        "error_code",
        "error_message",
        "redis_username",
      },
      request_transformer_advanced = {
        "dots_in_keys",
        replace = { "json_types", },
        add = { "json_types", },
        append = { "json_types", },
      },
    }, cp._get_removed_fields(2007000000))

    assert.same({
      zipkin = {
        "http_span_name",
        "connect_timeout",
        "send_timeout",
        "read_timeout",
      },
      opa = {
        "include_uri_captures_in_opa_input",
        "include_body_in_opa_input",
        "include_parsed_json_body_in_opa_input",
        "ssl_verify",
      },
      degraphql = {
        "graphql_server_path",
      },
      opentelemetry = {
        "connect_timeout",
        "send_timeout",
        "read_timeout",
      },
      prometheus = {
        "status_code_metrics",
        "latency_metrics",
        "bandwidth_metrics",
        "upstream_health_metrics",
      },
      pre_function = {
        "ws_handshake",
        "ws_client_frame",
        "ws_upstream_frame",
        "ws_close",
      },
      post_function = {
        "ws_handshake",
        "ws_client_frame",
        "ws_upstream_frame",
        "ws_close",
      },
      acme = {
        "allow_any_domain",
      },
      aws_lambda = {
        "aws_assume_role_arn",
        "aws_role_session_name",
      },
      mtls_auth = {
        "allow_partial_chain",
        "http_proxy_host",
        "http_proxy_port",
        "https_proxy_host",
        "https_proxy_port",
      },
      statsd_advanced = {
        "consumer_identifier_default",
        "service_identifier_default",
        "workspace_identifier_default",
      },
      statsd = {
        "allow_status_codes",
        "udp_packet_size",
        "use_tcp",
        "hostname_in_prefix",
        "consumer_identifier_default",
        "service_identifier_default",
        "workspace_identifier_default",
      },
      ldap_auth_advanced = {
        "groups_required"
      },
      forward_proxy = {
        "x_headers",
      },
      rate_limiting_advanced = {
        "disable_penalty",
      },
      rate_limiting = {
        "error_code",
        "error_message",
      },
      request_transformer_advanced = {
        "dots_in_keys",
        replace = { "json_types", },
        add = { "json_types", },
        append = { "json_types", },
      },
    }, cp._get_removed_fields(2008000000))

    assert.same({
      zipkin = {
        "http_span_name",
        "connect_timeout",
        "send_timeout",
        "read_timeout",
      },
      opa = {
        "include_uri_captures_in_opa_input",
        "include_body_in_opa_input",
        "include_parsed_json_body_in_opa_input",
        "ssl_verify",
      },
      degraphql = {
        "graphql_server_path",
      },
      opentelemetry = {
        "connect_timeout",
        "send_timeout",
        "read_timeout",
      },
      prometheus = {
        "status_code_metrics",
        "latency_metrics",
        "bandwidth_metrics",
        "upstream_health_metrics",
      },
      pre_function = {
        "ws_handshake",
        "ws_client_frame",
        "ws_upstream_frame",
        "ws_close",
      },
      post_function = {
        "ws_handshake",
        "ws_client_frame",
        "ws_upstream_frame",
        "ws_close",
      },
      acme = {
        "allow_any_domain",
      },
      aws_lambda = {
        "aws_assume_role_arn",
        "aws_role_session_name",
      },
      statsd_advanced = {
        "consumer_identifier_default",
        "service_identifier_default",
        "workspace_identifier_default",
      },
      statsd = {
        "allow_status_codes",
        "udp_packet_size",
        "use_tcp",
        "hostname_in_prefix",
        "consumer_identifier_default",
        "service_identifier_default",
        "workspace_identifier_default",
      },
      ldap_auth_advanced = {
        "groups_required"
      },
      forward_proxy = {
        "x_headers",
      },
      rate_limiting_advanced = {
        "disable_penalty",
      },
      rate_limiting = {
        "error_code",
        "error_message",
      },
      mtls_auth = {
        "allow_partial_chain",
      },
      request_transformer_advanced = {
        "dots_in_keys",
        replace = { "json_types", },
        add = { "json_types", },
        append = { "json_types", },
      },
    }, cp._get_removed_fields(2008001001))

    assert.same({
      zipkin = {
        "http_span_name",
        "connect_timeout",
        "send_timeout",
        "read_timeout",
      },
      opa = {
        "include_uri_captures_in_opa_input",
        "include_body_in_opa_input",
        "include_parsed_json_body_in_opa_input",
        "ssl_verify",
      },
      degraphql = {
        "graphql_server_path",
      },
      opentelemetry = {
        "connect_timeout",
        "send_timeout",
        "read_timeout",
      },
      prometheus = {
        "status_code_metrics",
        "latency_metrics",
        "bandwidth_metrics",
        "upstream_health_metrics",
      },
      pre_function = {
        "ws_handshake",
        "ws_client_frame",
        "ws_upstream_frame",
        "ws_close",
      },
      post_function = {
        "ws_handshake",
        "ws_client_frame",
        "ws_upstream_frame",
        "ws_close",
      },
      acme = {
        "allow_any_domain",
      },
      aws_lambda = {
        "aws_assume_role_arn",
        "aws_role_session_name",
      },
      statsd_advanced = {
        "consumer_identifier_default",
        "service_identifier_default",
        "workspace_identifier_default",
      },
      statsd = {
        "allow_status_codes",
        "udp_packet_size",
        "use_tcp",
        "hostname_in_prefix",
        "consumer_identifier_default",
        "service_identifier_default",
        "workspace_identifier_default",
      },
      ldap_auth_advanced = {
        "groups_required"
      },
      forward_proxy = {
        "x_headers",
      },
      rate_limiting_advanced = {
        "disable_penalty",
      },
      rate_limiting = {
        "error_code",
        "error_message",
      },
      mtls_auth = {
        "allow_partial_chain",
      },
      request_transformer_advanced = {
        "dots_in_keys",
        replace = { "json_types", },
        add = { "json_types", },
        append = { "json_types", },
      },
    }, cp._get_removed_fields(2008001002))

    assert.same({
      zipkin = {
        "http_span_name",
        "connect_timeout",
        "send_timeout",
        "read_timeout",
      },
      opa = {
        "include_uri_captures_in_opa_input",
        "include_body_in_opa_input",
        "include_parsed_json_body_in_opa_input",
        "ssl_verify",
      },
      degraphql = {
        "graphql_server_path",
      },
      opentelemetry = {
        "connect_timeout",
        "send_timeout",
        "read_timeout",
      },
      prometheus = {
        "status_code_metrics",
        "latency_metrics",
        "bandwidth_metrics",
        "upstream_health_metrics",
      },
      pre_function = {
        "ws_handshake",
        "ws_client_frame",
        "ws_upstream_frame",
        "ws_close",
      },
      post_function = {
        "ws_handshake",
        "ws_client_frame",
        "ws_upstream_frame",
        "ws_close",
      },
      statsd_advanced = {
        "consumer_identifier_default",
        "service_identifier_default",
        "workspace_identifier_default",
      },
      statsd = {
        "allow_status_codes",
        "udp_packet_size",
        "use_tcp",
        "hostname_in_prefix",
        "consumer_identifier_default",
        "service_identifier_default",
        "workspace_identifier_default",
      },
      ldap_auth_advanced = {
        "groups_required"
      },
      forward_proxy = {
        "x_headers",
      },
      rate_limiting_advanced = {
        "disable_penalty",
      },
      rate_limiting = {
        "error_code",
        "error_message",
      },
      mtls_auth = {
        "allow_partial_chain",
      },
      request_transformer_advanced = {
        "dots_in_keys",
        replace = { "json_types", },
        add = { "json_types", },
        append = { "json_types", },
      },
    }, cp._get_removed_fields(2008001003))

    assert.same({
      degraphql = {
        "graphql_server_path",
      },
      forward_proxy = {
        "x_headers",
      },
      ldap_auth_advanced = {
        "groups_required",
      },
      mtls_auth = {
        "allow_partial_chain",
      },
      opa = {
        "include_uri_captures_in_opa_input",
        "include_body_in_opa_input",
        "include_parsed_json_body_in_opa_input",
        "ssl_verify",
      },
      opentelemetry = {
        "connect_timeout",
        "send_timeout",
        "read_timeout",
      },
      post_function = {
        "ws_handshake",
        "ws_client_frame",
        "ws_upstream_frame",
        "ws_close",
      },
      pre_function = {
        "ws_handshake",
        "ws_client_frame",
        "ws_upstream_frame",
        "ws_close",
      },
      prometheus = {
        "status_code_metrics",
        "latency_metrics",
        "bandwidth_metrics",
        "upstream_health_metrics",
      },
      rate_limiting = {
        "error_code",
        "error_message",
      },
      rate_limiting_advanced = {
        "disable_penalty",
      },
      request_transformer_advanced = {
        "dots_in_keys",
        replace = { "json_types", },
        add = { "json_types", },
        append = { "json_types", },
      },
      statsd = {
        "allow_status_codes",
        "udp_packet_size",
        "use_tcp",
        "hostname_in_prefix",
        "consumer_identifier_default",
        "service_identifier_default",
        "workspace_identifier_default",
      },
      statsd_advanced = {
        "consumer_identifier_default",
        "service_identifier_default",
        "workspace_identifier_default",
      },
      zipkin = {
        "http_span_name",
        "connect_timeout",
        "send_timeout",
        "read_timeout",
      },
    }, cp._get_removed_fields(2008001004))

    assert.same({
      degraphql = {
        "graphql_server_path",
      },
      forward_proxy = {
        "x_headers",
      },
      ldap_auth_advanced = {
        "groups_required",
      },
      mtls_auth = {
        "allow_partial_chain",
      },
      opa = {
        "include_uri_captures_in_opa_input",
        "include_body_in_opa_input",
        "include_parsed_json_body_in_opa_input",
        "ssl_verify",
      },
      opentelemetry = {
        "connect_timeout",
        "send_timeout",
        "read_timeout",
      },
      post_function = {
        "ws_handshake",
        "ws_client_frame",
        "ws_upstream_frame",
        "ws_close",
      },
      pre_function = {
        "ws_handshake",
        "ws_client_frame",
        "ws_upstream_frame",
        "ws_close",
      },
      prometheus = {
        "status_code_metrics",
        "latency_metrics",
        "bandwidth_metrics",
        "upstream_health_metrics",
      },
      rate_limiting = {
        "error_code",
        "error_message",
      },
      rate_limiting_advanced = {
        "disable_penalty",
      },
      request_transformer_advanced = {
        "dots_in_keys",
        replace = { "json_types", },
        add = { "json_types", },
        append = { "json_types", },
      },
      statsd = {
        "allow_status_codes",
        "udp_packet_size",
        "use_tcp",
        "hostname_in_prefix",
        "consumer_identifier_default",
        "service_identifier_default",
        "workspace_identifier_default",
      },
      statsd_advanced = {
        "consumer_identifier_default",
        "service_identifier_default",
        "workspace_identifier_default",
      },
      zipkin = {
        "http_span_name",
        "connect_timeout",
        "send_timeout",
        "read_timeout",
      },
    }, cp._get_removed_fields(2008002000))

    assert.same({
      opa = {
        "include_uri_captures_in_opa_input",
      },
      forward_proxy = {
        "x_headers",
      },
      rate_limiting = {
        "error_code",
        "error_message",
      },
      rate_limiting_advanced = {
        "disable_penalty",
      },
      mtls_auth = {
        "allow_partial_chain",
      },
    }, cp._get_removed_fields(3000000000))

    assert.same({
      forward_proxy = {
        "x_headers",
      },
      opa = {
        "include_uri_captures_in_opa_input",
      },
      rate_limiting_advanced = {
        "disable_penalty",
      },
      rate_limiting = {
        "error_code",
        "error_message",
      },
      mtls_auth = {
        "allow_partial_chain",
      },
    }, cp._get_removed_fields(3000001000))
    assert.same(nil, cp._get_removed_fields(3001000000))

  end)

  it("update or remove unknown fields", function()
    local test_with = function(payload, dp_version)
      local has_update, deflated_payload, err = cp._update_compatible_payload(
        payload, dp_version, ""
      )
      assert(err == nil)
      if has_update then
        local result = cjson_decode(inflate_gzip(deflated_payload))
        if payload._format_version then
          assert.same("2.1", result.config_table._format_version)
        end
        return result
      end

      return payload
    end

    assert.same({config_table = {}}, test_with({config_table = {}}, "2.3.0"))

    local payload

    payload = {
      config_table ={
        plugins = {
        }
      }
    }
    assert.same(payload, test_with(payload, "2.3.0"))

    payload = {
      config_table ={
        plugins = { {
          name = "prometheus",
          config = {
            per_consumer = true,
          },
        }, {
          name = "syslog",
          config = {
            custom_fields_by_lua = true,
            facility = "user",
          }
        }, {
          name = "redis-advanced",
          config = {
            redis = {
              "connect_timeout",
              "keepalive_backlog",
              "keepalive_pool_size",
              "read_timeout",
              "send_timeout",
              "username",
              "sentinel_username",
            },
          }
        }, {
          name = "rate-limiting-advanced",
          config = {
            limit = 5,
            identifier = "path",
            window_size = 30,
            strategy = "local",
            path = "/test",
          }
        }, {
          name = "datadog",
          config = {
            service_name_tag= "ok",
            status_tag= "ok",
            consumer_tag = "ok",
            metrics = {
              {
                name = "request_count",
                stat_type = "distribution",
              },
            }
          }
        }, {
          name = "zipkin",
          config = {
            local_service_name = "ok",
            header_type = "ignore"
          }
        }, {
          name = "openid-connect",
          config = {
            session_redis_password = "test",
          }
        }, {
          name = "forward-proxy",
          config = {
            http_proxy_host = "test.com",
            http_proxy_port = "80",
          },
        }, {
          name = "kafka-log",
          config = {
            cluster_name = "test",
          }
        }, {
          name = "kafka-upstream",
          config = {
            cluster_name = "test",
          },
        }, {
          name = "pre-function",
          config = {
            access            = { [[error("oh no!")]] },
            log               = { [[error("oh no!")]] },
            ws_handshake      = { [[error("oh no!")]] },
            ws_client_frame   = { [[error("oh no!")]] },
            ws_upstream_frame = { [[error("oh no!")]] },
            ws_close          = { [[error("oh no!")]] },
          },
        }, {
          name = "post-function",
          config = {
            access            = { [[error("oh no!")]] },
            log               = { [[error("oh no!")]] },
            ws_handshake      = { [[error("oh no!")]] },
            ws_client_frame   = { [[error("oh no!")]] },
            ws_upstream_frame = { [[error("oh no!")]] },
            ws_close          = { [[error("oh no!")]] },
          },
        }, }
      }
    }
    assert.same({ {
      name = "prometheus",
      config = {
        -- per_consumer = true, -- this is removed
      },
    }, {
      name = "syslog",
      config = {
        -- custom_fields_by_lua = true, -- this is removed
        -- facility = "user", -- this is removed
      }
    }, {
      name = "redis-advanced",
      config = {
        redis = {
          "connect_timeout",
          "keepalive_backlog",
          "keepalive_pool_size",
          "read_timeout",
          "send_timeout",
          "username",
          "sentinel_username",
        },
      }
    }, {
      name = "rate-limiting-advanced",
      config = {
        limit = 5,
        identifier = "consumer",
        window_size = 30,
        strategy = "redis",
        sync_rate = -1,
      }
    }, {
      name = "datadog",
      config = { metrics={}, }
    }, {
      name = "zipkin",
      config = {
        header_type = "preserve"
      }
    }, {
      name = "openid-connect",
      config = {
        session_redis_auth = "test",
      }
    }, {
      name = "forward-proxy",
      config = {
        proxy_host = "test.com",
        proxy_port = "80",
      }
    }, {
      name = "kafka-log",
      config = {}
    }, {
      name = "kafka-upstream",
      config = {}
    }, {
      name = "pre-function",
      config = {
        access = { [[error("oh no!")]] },
        log    = { [[error("oh no!")]] },
      }
    }, {
      name = "post-function",
      config = {
        access = { [[error("oh no!")]] },
        log    = { [[error("oh no!")]] },
      }
    }, }, test_with(payload, "2.3.0").config_table.plugins)

    assert.same({ {
      name = "prometheus",
      config = {
        per_consumer = true,
      },
    }, {
      name = "syslog",
      config = {
        custom_fields_by_lua = true,
        -- facility = "user", -- this is removed
      }
    }, {
      name = "redis-advanced",
      config = {
        redis = {
          "connect_timeout",
          "keepalive_backlog",
          "keepalive_pool_size",
          "read_timeout",
          "send_timeout",
          "username",
          "sentinel_username",
        },
      }
    }, {
      name = "rate-limiting-advanced",
      config = {
        limit = 5,
        identifier = "consumer",
        window_size = 30,
        strategy = "redis",
        sync_rate = -1,
      }
    }, {
      name = "datadog",
      config = { metrics={}, }
    }, {
      name = "zipkin",
      config = {
        header_type = "preserve"
      }
    }, {
      name = "openid-connect",
      config = {
        session_redis_auth = "test",
      }
    }, {
      name = "forward-proxy",
      config = {
        proxy_host = "test.com",
        proxy_port = "80",
      }
    }, {
      name = "kafka-log",
      config = {}
    }, {
      name = "kafka-upstream",
      config = {}
    }, {
      name = "pre-function",
      config = {
        access = { [[error("oh no!")]] },
        log    = { [[error("oh no!")]] },
      }
    }, {
      name = "post-function",
      config = {
        access = { [[error("oh no!")]] },
        log    = { [[error("oh no!")]] },
      }
    }, }, test_with(payload, "2.4.0").config_table.plugins)

    assert.same({ {
      name = "prometheus",
      config = {
        per_consumer = true,
      },
    }, {
      name = "syslog",
      config = {
        custom_fields_by_lua = true,
        facility = "user",
      }
    }, {
      name = "redis-advanced",
      config = {
        redis = {
          "connect_timeout",
          "keepalive_backlog",
          "keepalive_pool_size",
          "read_timeout",
          "send_timeout",
          "username",
          "sentinel_username",
        },
      }
    }, {
      name = "rate-limiting-advanced",
      config = {
        limit = 5,
        identifier = "consumer",
        window_size = 30,
        strategy = "redis",
        sync_rate = -1,
      }
    }, {
      name = "datadog",
      config = { metrics={}, }
    }, {
      name = "zipkin",
      config = {
        header_type = "preserve"
      }
    }, {
      name = "openid-connect",
      config = {
        session_redis_auth = "test",
      }
    }, {
      name = "forward-proxy",
      config = {
        proxy_host = "test.com",
        proxy_port = "80",
      }
    }, {
      name = "kafka-log",
      config = {}
    }, {
      name = "kafka-upstream",
      config = {}
    }, {
      name = "pre-function",
      config = {
        access = { [[error("oh no!")]] },
        log    = { [[error("oh no!")]] },
      }
    }, {
      name = "post-function",
      config = {
        access = { [[error("oh no!")]] },
        log    = { [[error("oh no!")]] },
      }
    }, }, test_with(payload, "2.5.0").config_table.plugins)

    assert.same({ {
      name = "prometheus",
      config = {
        per_consumer = true,
      },
    }, {
      name = "syslog",
      config = {
        custom_fields_by_lua = true,
        facility = "user",
      }
    }, {
      name = "redis-advanced",
      config = {
        redis = {
          "connect_timeout",
          "keepalive_backlog",
          "keepalive_pool_size",
          "read_timeout",
          "send_timeout",
          "username",
          "sentinel_username",
        },
      }
    }, {
      name = "rate-limiting-advanced",
      config = {
        limit = 5,
        identifier = "path",
        window_size = 30,
        strategy = "local",
        path = "/test",
      }
    }, {
      name = "datadog",
      config = { metrics={}, }
    }, {
      name = "zipkin",
      config = {
        header_type = "preserve"
      }
    }, {
      name = "openid-connect",
      config = {
        session_redis_auth = "test",
      }
    }, {
      name = "forward-proxy",
      config = {
        proxy_host = "test.com",
        proxy_port = "80",
      }
    }, {
      name = "kafka-log",
      config = {}
    }, {
      name = "kafka-upstream",
      config = {}
    }, {
      name = "pre-function",
      config = {
        access = { [[error("oh no!")]] },
        log    = { [[error("oh no!")]] },
      }
    }, {
      name = "post-function",
      config = {
        access = { [[error("oh no!")]] },
        log    = { [[error("oh no!")]] },
      }
    }, }, test_with(payload, "2.6.0").config_table.plugins)

    assert.same({ {
      name = "prometheus",
      config = {
        per_consumer = true,
      },
    }, {
      name = "syslog",
      config = {
        custom_fields_by_lua = true,
        facility = "user",
      }
    }, {
      name = "redis-advanced",
      config = {
        redis = {
          "connect_timeout",
          "keepalive_backlog",
          "keepalive_pool_size",
          "read_timeout",
          "send_timeout",
          "username",
          "sentinel_username",
        },
      }
    }, {
      name = "rate-limiting-advanced",
      config = {
        limit = 5,
        identifier = "path",
        window_size = 30,
        strategy = "local",
        path = "/test",
      }
    }, {
      name = "datadog",
      config = {
        service_name_tag= "ok",
        status_tag= "ok",
        consumer_tag = "ok",
        metrics = {
          {
            name = "request_count",
            stat_type = "distribution",
          },
        }
      }
    }, {
      name = "zipkin",
      config = {
        local_service_name = "ok",
        header_type = "ignore"
      }
    }, {
      name = "openid-connect",
      config = {
        session_redis_auth = "test",
      }
    }, {
      name = "forward-proxy",
      config = {
        proxy_host = "test.com",
        proxy_port = "80",
      }
    }, {
      name = "kafka-log",
      config = {}
    }, {
      name = "kafka-upstream",
      config = {}
    }, {
      name = "pre-function",
      config = {
        access = { [[error("oh no!")]] },
        log    = { [[error("oh no!")]] },
      }
    }, {
      name = "post-function",
      config = {
        access = { [[error("oh no!")]] },
        log    = { [[error("oh no!")]] },
      }
    }, }, test_with(payload, "2.7.0").config_table.plugins)

    -- nothing should be removed
    assert.same(payload.config_table.plugins, test_with(payload, "3.0.0").config_table.plugins)

    -- test that the RLA sync_rate is updated
    payload = {
      config_table = {
        plugins = { {
          name = "rate-limiting-advanced",
          config = {
            sync_rate = 0.001,
          }
        } }
      }
    }

    assert.same({{
      name = "rate-limiting-advanced",
      config = {
        sync_rate = 1,
      }
    } }, test_with(payload, "2.5.0").config_table.plugins)
  end)

  it("update or remove unknown field elements", function()
    local test_with = function(payload, dp_version)
      local has_update, deflated_payload, err = cp._update_compatible_payload(
        payload, dp_version, ""
      )
      assert(err == nil)
      if has_update then
        return cjson_decode(inflate_gzip(deflated_payload))
      end

      return payload
    end

    local payload = {
      config_table ={
        plugins = { {
          name = "openid-connect",
          config = {
            auth_methods = {
              "password",
              "client_credentials",
              "authorization_code",
              "bearer",
              "introspection",
              "userinfo",
              "kong_oauth2",
              "refresh_token",
              "session",
            },
            ignore_signature = {
              "password",
              "client_credentials",
              "authorization_code",
              "refresh_token",
              "session",
              "introspection",
              "userinfo",
            },
          },
        }, {
          name = "syslog",
          config = {
            custom_fields_by_lua = true,
            facility = "user",
          }
        }, {
          name = "rate-limiting-advanced",
          config = {
            identifier = "path",
          }
        }, {
          name = "canary",
          config = {
            hash = "header",
          }
        }, }
      }
    }
    assert.same({ {
      name = "openid-connect",
      config = {
        auth_methods = {
          "password",
          "client_credentials",
          "authorization_code",
          "bearer",
          "introspection",
          -- "userinfo", -- this element is removed
          "kong_oauth2",
          "refresh_token",
          "session",
        },
        ignore_signature = {
          "password",
          "client_credentials",
          "authorization_code",
          "refresh_token",
          "session",
          -- "introspection", -- this element is removed
          -- "userinfo", -- this element is removed
        },
      },
    }, {
      name = "syslog",
      config = {
        -- custom_fields_by_lua = true, -- this is removed
        -- facility = "user", -- this is removed
      }
    }, {
      name = "rate-limiting-advanced",
      config = {
        identifier = "consumer",  -- was path, fallback to default consumer
      }
    }, {
      name = "canary",
      config = {
        hash = "consumer",
      }
    } }, test_with(payload, "2.3.0").config_table.plugins)

    assert.same({ {
      name = "openid-connect",
      config = {
        auth_methods = {
          "password",
          "client_credentials",
          "authorization_code",
          "bearer",
          "introspection",
          -- "userinfo", -- this element is removed
          "kong_oauth2",
          "refresh_token",
          "session",
        },
        ignore_signature = {
          "password",
          "client_credentials",
          "authorization_code",
          "refresh_token",
          "session",
          -- "introspection", -- this element is removed
          -- "userinfo", -- this element is removed
        },
      },
    }, {
      name = "syslog",
      config = {
        custom_fields_by_lua = true,
        facility = "user",
      }
    }, {
      name = "rate-limiting-advanced",
      config = {
        identifier = "consumer",  -- was path, fallback to default consumer
      }
    }, {
      name = "canary",
      config = {
        hash = "consumer",
      }
    } }, test_with(payload, "2.5.0").config_table.plugins)

    -- nothing should be removed
    assert.same(payload.config_table.plugins, test_with(payload, "2.6.0").config_table.plugins)

    local payload = {
      config_table ={
        plugins = { {
          name = "kafka-upstream",
          config = {
            authentication = {
              mechanism = "SCRAM-SHA-512",
            }}}}}}
    assert.same({ {
      name = "kafka-upstream",
      config = {
        authentication = {
          mechanism = "SCRAM-SHA-256",
      },
    },
    } }, test_with(payload, "2.7.0").config_table.plugins)
    assert.same({ {
      name = "kafka-upstream",
      config = {
        authentication = {
          mechanism = "SCRAM-SHA-256",
      },
    },
    } }, test_with(payload, "2.8.0").config_table.plugins)

    assert.same({ {
      name = "kafka-upstream",
      config = {
        authentication = {
          mechanism = "SCRAM-SHA-256",
      },
    },
    } }, test_with(payload, "2.8.1.0").config_table.plugins)
    -- 2.8.1.1 is fine here
    assert.same(payload.config_table.plugins, test_with(payload, "2.8.1.1").config_table.plugins)

    local payload = {
      config_table ={
        plugins = { {
          name = "kafka-log",
          config = {
            authentication = {
              mechanism = "SCRAM-SHA-512",
            }}}}}}
    assert.same({ {
      name = "kafka-log",
      config = {
        authentication = {
          mechanism = "SCRAM-SHA-256",
      },
    },
    } }, test_with(payload, "2.7.0").config_table.plugins)
    assert.same({ {
      name = "kafka-log",
      config = {
        authentication = {
          mechanism = "SCRAM-SHA-256",
      },
    },
    } }, test_with(payload, "2.8.0").config_table.plugins)
    assert.same({ {
      name = "kafka-log",
      config = {
        authentication = {
          mechanism = "SCRAM-SHA-256",
      },
    },
    } }, test_with(payload, "2.8.1.0").config_table.plugins)
    -- 2.8.1.1 is fine here
    assert.same(payload.config_table.plugins, test_with(payload, "2.8.1.1").config_table.plugins)
  end)
end)
