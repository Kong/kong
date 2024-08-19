-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local schema_def = require "kong.plugins.confluent.schema"
local v = require("spec.helpers").validate_plugin_config_schema

local base_config = {
  bootstrap_servers = {
    { host = "foo", port = 8080 }
  },
  topic = "test-topic",
  cluster_api_key = "foo",
  cluster_api_secret = "bar",
}

describe("Plugin: confluent (schema)", function()

  it("validates emtpy config", function()
    -- empty config is not allowed
    local ok, err = v({}, schema_def)
    assert.is_truthy(err)
    assert.is_nil(ok)
  end)

  it("validates base config", function()
    -- base conf needs bootstrap_servers, topic and key/secret
    local ok, err = v(base_config, schema_def)
    assert.is_nil(err)
    assert.is_truthy(ok)
  end)

  describe("Producer schema:", function()
    it("validates producer_request_acks faulty#1", function()
      -- only -1, 0, 1 is valid
      base_config['producer_request_acks'] = 2
      local ok, err = v(base_config, schema_def)
      assert.same("expected one of: -1, 0, 1", err.config.producer_request_acks)
      assert.is_not_truthy(ok)
    end)
  end)
end)
