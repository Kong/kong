_G.kong = {
  configuration = {
    cluster_max_payload = 4194304
  }
}

local utils = require("kong.clustering.utils")

describe("kong.clustering.utils", function()
  it("calculating dp_version_num", function()
    assert.equal(2003004000, utils.version_num("2.3.4"))
    assert.equal(2003004000, utils.version_num("2.3.4-rc1"))
    assert.equal(2003004000, utils.version_num("2.3.4beta2"))
    assert.equal(2003004001, utils.version_num("2.3.4.1"))
    assert.equal(2003004001, utils.version_num("2.3.4.1-rc1"))
    assert.equal(2003004001, utils.version_num("2.3.4.1beta2"))
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
      },
      redis = {
        "connect_timeout",
        "keepalive_backlog",
        "keepalive_pool_size",
        "read_timeout",
        "send_timeout",
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
      rate_limiting = {
        "error_code",
        "error_message",
        "redis_ssl",
        "redis_ssl_verify",
        "redis_server_name",
      },
      response_ratelimiting = {
        "redis_ssl",
        "redis_ssl_verify",
        "redis_server_name",
      },
    }, utils._get_removed_fields(2003000000))

    assert.same({
      redis = {
        "connect_timeout",
        "keepalive_backlog",
        "keepalive_pool_size",
        "read_timeout",
        "send_timeout",
      },
      syslog = {
        "facility",
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
      rate_limiting = {
        "error_code",
        "error_message",
        "redis_ssl",
        "redis_ssl_verify",
        "redis_server_name",
      },
      response_ratelimiting = {
        "redis_ssl",
        "redis_ssl_verify",
        "redis_server_name",
      },
    }, utils._get_removed_fields(2003003003))

    assert.same({
      redis = {
        "connect_timeout",
        "keepalive_backlog",
        "keepalive_pool_size",
        "read_timeout",
        "send_timeout",
      },
      syslog = {
        "facility",
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
      rate_limiting = {
        "error_code",
        "error_message",
        "redis_ssl",
        "redis_ssl_verify",
        "redis_server_name",
      },
      response_ratelimiting = {
        "redis_ssl",
        "redis_ssl_verify",
        "redis_server_name",
      },
    }, utils._get_removed_fields(2003004000))

    assert.same({
      redis = {
        "connect_timeout",
        "keepalive_backlog",
        "keepalive_pool_size",
        "read_timeout",
        "send_timeout",
      },
      syslog = {
        "facility",
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
      rate_limiting = {
        "error_code",
        "error_message",
        "redis_ssl",
        "redis_ssl_verify",
        "redis_server_name",
      },
      response_ratelimiting = {
        "redis_ssl",
        "redis_ssl_verify",
        "redis_server_name",
      },
    }, utils._get_removed_fields(2004001000))

    assert.same({
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
      rate_limiting = {
        "error_code",
        "error_message",
        "redis_ssl",
        "redis_ssl_verify",
        "redis_server_name",
      },
      response_ratelimiting = {
        "redis_ssl",
        "redis_ssl_verify",
        "redis_server_name",
      },
    }, utils._get_removed_fields(2004001002))

    assert.same({
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
      rate_limiting = {
        "error_code",
        "error_message",
        "redis_ssl",
        "redis_ssl_verify",
        "redis_server_name",
      },
      response_ratelimiting = {
        "redis_ssl",
        "redis_ssl_verify",
        "redis_server_name",
      },
    }, utils._get_removed_fields(2005000000))

    assert.same({
      rate_limiting = {
        "error_code",
        "error_message",
        "redis_ssl",
        "redis_ssl_verify",
        "redis_server_name",
      },
      response_ratelimiting = {
        "redis_ssl",
        "redis_ssl_verify",
        "redis_server_name",
      },
    }, utils._get_removed_fields(2006000000))

    assert.same({
      rate_limiting = {
        "error_code",
        "error_message",
      },
      response_ratelimiting = {
        "redis_ssl",
        "redis_ssl_verify",
        "redis_server_name",
      },
    }, utils._get_removed_fields(2007000000))
    assert.same({
      rate_limiting = {
        "error_code",
        "error_message",
      },
      response_ratelimiting = {
        "redis_ssl",
        "redis_ssl_verify",
        "redis_server_name",
      },
    }, utils._get_removed_fields(2008000000))
    assert.same(nil, utils._get_removed_fields(3001000000))
  end)

  it("removing unknown fields", function()
    local test_with = function(payload, dp_version)
      local has_update, new_conf = utils.update_compatible_payload(
        payload, dp_version, ""
      )

      if has_update then
        return new_conf
      end

      return payload
    end

    assert.same({}, test_with({}, "2.3.0"))

    local payload

    payload = {
      plugins = {
      }
    }
    assert.same(payload, test_with(payload, "2.3.0"))

    payload = {
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
      } }
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
    } }, test_with(payload, "2.3.0").plugins)

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
    } }, test_with(payload, "2.4.0").plugins)

    -- nothing should be removed
    assert.same(payload.plugins, test_with(payload, "2.5.0").plugins)
  end)
end)
