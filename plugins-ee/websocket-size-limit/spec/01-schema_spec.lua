-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]


local schema = require "kong.plugins.websocket-size-limit.schema"
local v = require("spec.helpers").validate_plugin_config_schema
local const = require "kong.enterprise_edition.constants"

local MAX = const.WEBSOCKET.MAX_PAYLOAD_SIZE

local function validate(conf)
  return v(conf, schema)
end

describe("Plugin: websocket-size-limit (schema)", function()
  it("accepts a valid config", function()
    local ok, err = validate({ client_max_payload = 1024 })
    assert.truthy(ok, err)

    ok, err = validate({ upstream_max_payload = 1024 })
    assert.truthy(ok, err)

    ok, err = validate({ client_max_payload = 1024, upstream_max_payload = 1024 })
    assert.truthy(ok, err)
  end)

  it("requires at least one of client/upstream fields", function()
    local ok, err = validate({})
    assert.is_nil(ok)
    assert.same({ config = { ["@entity"] = {
        "at least one of these fields must be non-empty: 'client_max_payload', 'upstream_max_payload'"
      }}}, err)
  end)

  it("validates that the limit is in the proper range", function()
    local msg = ("value should be between 1 and %s"):format(MAX)

    for _, value in ipairs({ 0, -1, MAX + 1 }) do
      local ok, err = validate({
        client_max_payload   = value,
        upstream_max_payload = value,
      })

      assert.is_nil(ok)
      assert.same(
        { config = {
            client_max_payload   = msg,
            upstream_max_payload = msg,
          }
        }, err)
    end
  end)
end)
