-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

_G.kong = {
  -- XXX EE: kong.version is used in some warning messages in
  -- clustering/control_plane.lua and fail if nil
  version = "x.y.z"
}

local cp = require("kong.clustering.control_plane")
local cjson_decode = require("cjson").decode
local inflate_gzip = require("kong.tools.utils").inflate_gzip

describe("kong.clustering.control_plane", function()
  it("calculating dp_version_num", function()
    assert.equal(2003004000, cp._dp_version_num("2.3.4"))
    assert.equal(2003004000, cp._dp_version_num("2.3.4-rc1"))
    assert.equal(2003004000, cp._dp_version_num("2.3.4beta2"))
    assert.equal(2003004001, cp._dp_version_num("2.3.4.1"))
    assert.equal(2003004001, cp._dp_version_num("2.3.4.1-rc1"))
    assert.equal(2003004001, cp._dp_version_num("2.3.4.1beta2"))
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
        "per_consumer",
      },
      syslog = {
        "custom_fields_by_lua",
        "facility",
      },
      tcp_log = {
        "custom_fields_by_lua",
      },
      udp_log = {
        "custom_fields_by_lua",
      },
      zipkin = {
        "tags_header",
        "local_service_name",
      },
      redis = {
        "connect_timeout",
        "keepalive_backlog",
        "read_timeout",
        "send_timeout",
        "keepalive_pool_size",
      },
      acme = {
        "preferred_chain",
        "rsa_key_size",
      },
      aws_lambda = {
        "base64_encode_body",
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
      },
      kafka_log = {
        "authentication",
        "keepalive_enabled",
        "security",
      },
      kafka_upstream = {
        "authentication",
        "keepalive_enabled",
        "security",
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
        "enforce_consumer_groups",
        "consumer_groups",
      },
      forward_proxy = {
        "auth_username",
        "auth_password"
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
        "redis_ssl",
        "redis_ssl_verify",
        "redis_server_name",
      },
    }, cp._get_removed_fields(2003000000))

    assert.same({
      redis = {
        "connect_timeout",
        "keepalive_backlog",
        "read_timeout",
        "send_timeout",
        "keepalive_pool_size",
      },
      prometheus = {
        "per_consumer",
      },
      zipkin = {
        "tags_header",
        "local_service_name",
      },
      syslog = {
        "facility",
      },
      acme = {
        "preferred_chain",
        "rsa_key_size",
      },
      aws_lambda = {
        "base64_encode_body",
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
      },
      kafka_log = {
        "authentication",
        "keepalive_enabled",
        "security",
      },
      kafka_upstream = {
        "authentication",
        "keepalive_enabled",
        "security",
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
        "enforce_consumer_groups",
        "consumer_groups",
      },
      forward_proxy = {
        "auth_username",
        "auth_password"
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
        "redis_ssl",
        "redis_ssl_verify",
        "redis_server_name",
      },
    }, cp._get_removed_fields(2003003003))

    assert.same({
      redis = {
        "connect_timeout",
        "keepalive_backlog",
        "read_timeout",
        "send_timeout",
        "keepalive_pool_size",
      },
      syslog = {
        "facility",
      },
      prometheus = {
        "per_consumer",
      },
      zipkin = {
        "tags_header",
        "local_service_name",
      },
      acme = {
        "preferred_chain",
        "rsa_key_size",
      },
      aws_lambda = {
        "base64_encode_body",
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
      },
      kafka_log = {
        "authentication",
        "keepalive_enabled",
        "security",
      },
      kafka_upstream = {
        "authentication",
        "keepalive_enabled",
        "security",
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
        "enforce_consumer_groups",
        "consumer_groups",
      },
      forward_proxy = {
        "auth_username",
        "auth_password"
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
        "redis_ssl",
        "redis_ssl_verify",
        "redis_server_name",
      },
    }, cp._get_removed_fields(2003004000))

    assert.same({
      redis = {
        "connect_timeout",
        "keepalive_backlog",
        "read_timeout",
        "send_timeout",
        "keepalive_pool_size",
      },
      syslog = {
        "facility",
      },
      acme = {
        "preferred_chain",
        "rsa_key_size",
      },
      aws_lambda = {
        "base64_encode_body",
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
      },
      kafka_log = {
        "authentication",
        "keepalive_enabled",
        "security",
      },
      kafka_upstream = {
        "authentication",
        "keepalive_enabled",
        "security",
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
        "enforce_consumer_groups",
        "consumer_groups",
      },
      forward_proxy = {
        "auth_username",
        "auth_password"
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
        "redis_ssl",
        "redis_ssl_verify",
        "redis_server_name",
      },
      zipkin = {
        "local_service_name",
      },
    }, cp._get_removed_fields(2004001000))

    assert.same({
      redis = {
        "keepalive_pool_size",
      },
      acme = {
        "preferred_chain",
        "rsa_key_size",
      },
      aws_lambda = {
        "base64_encode_body",
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
      },
      kafka_log = {
        "authentication",
        "keepalive_enabled",
        "security",
      },
      kafka_upstream = {
        "authentication",
        "keepalive_enabled",
        "security",
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
        "enforce_consumer_groups",
        "consumer_groups",
      },
      forward_proxy = {
        "auth_username",
        "auth_password"
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
        "redis_ssl",
        "redis_ssl_verify",
        "redis_server_name",
      },
      zipkin = {
        "local_service_name",
      },
    }, cp._get_removed_fields(2004001002))

    assert.same({
      acme = {
        "preferred_chain",
        "rsa_key_size",
      },
      aws_lambda = {
        "base64_encode_body",
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
      },
      kafka_log = {
        "authentication",
        "keepalive_enabled",
        "security",
      },
      kafka_upstream = {
        "authentication",
        "keepalive_enabled",
        "security",
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
        "enforce_consumer_groups",
        "consumer_groups",
      },
      forward_proxy = {
        "auth_username",
        "auth_password"
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
        "redis_ssl",
        "redis_ssl_verify",
        "redis_server_name",
      },
      zipkin = {
        "local_service_name",
      },
    }, cp._get_removed_fields(2005000000))

    assert.same({
      acme = {
        "rsa_key_size",
      },
      forward_proxy = {
        "auth_username",
        "auth_password"
      },
      mocking = {
        "random_examples",
      },
      rate_limiting_advanced = {
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
        "redis_ssl",
        "redis_ssl_verify",
        "redis_server_name",
      },
      zipkin = {
        "local_service_name",
      },
    }, cp._get_removed_fields(2006000000))

    assert.same({
      acme = {
        "rsa_key_size",
      },
    }, cp._get_removed_fields(2007000000))

    assert.same(nil, cp._get_removed_fields(2008000000))
  end)

  it("update or remove unknown fields", function()
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
    } }, test_with(payload, "2.3.0").config_table.plugins)

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
    } }, test_with(payload, "2.4.0").config_table.plugins)

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
    } }, test_with(payload, "2.5.0").config_table.plugins)

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
    } }, test_with(payload, "2.6.0").config_table.plugins)

    -- nothing should be removed
    assert.same(payload.config_table.plugins, test_with(payload, "2.7.0").config_table.plugins)

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
  end)
end)
