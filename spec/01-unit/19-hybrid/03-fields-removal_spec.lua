-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

_G.kong = {}

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
      },
      redis = {
        "connect_timeout",
        "keepalive_backlog",
        "keepalive_pool_size",
        "read_timeout",
        "send_timeout",
      },
    }, cp._get_removed_fields(2003000000))

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
      }
    }, cp._get_removed_fields(2003003003))

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
      }
    }, cp._get_removed_fields(2003004000))
  
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
      }
    }, cp._get_removed_fields(2004001000))

    assert.same(nil, cp._get_removed_fields(2004001002))
    assert.same(nil, cp._get_removed_fields(2005000000))
  end)

  it("removing unknonwn fields", function()
    local test_with = function(payload, dp_version)
      local has_update, deflated_payload, err = cp._update_compatible_payload(
        payload, dp_version
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
        } }
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
    } }, test_with(payload, "2.4.0").config_table.plugins)

    -- nothing should be removed
    assert.same(payload.config_table.plugins, test_with(payload, "2.5.0").config_table.plugins)
  end)
end)
