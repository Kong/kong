-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local schema_def = require "kong.plugins.kafka-log.schema"
local v = require("spec.helpers").validate_plugin_config_schema

local base_config = {
  bootstrap_servers = {
    { host = "foo", port = 8080 }
  },
  topic = "test-topic"
}

describe("Plugin: kafka-log (schema)", function()
  before_each(function()
    base_config.authentication = {}
    base_config.security = {}
  end)

  it("validates emtpy config", function()
    -- empty config is not allowed
    local ok, err = v({}, schema_def)
    assert.is_truthy(err)
    assert.is_nil(ok)
  end)

  it("validates base config", function()
    -- base conf needs bootstrap_servers and topic, rest is inferred
    local ok, err = v(base_config, schema_def)
    assert.is_nil(err)
    assert.is_truthy(ok)
  end)

  it("accepts custom fields by lua", function()
    -- add custom_fields_by_lua
    local ok, err = v({
      bootstrap_servers = {
        { host = "foo", port = 8080 }
      },
      topic = "test-topic",
      custom_fields_by_lua = {
        foo = "return 'bar'",
      }
    }, schema_def)
    assert.is_nil(err)
    assert.is_truthy(ok)
  end)

  describe("Auth schema:", function()
    it("validates authentication SASL/PLAIN", function()
      -- authentication requires 4 entries. constraints apply
      local auth_config = {
        strategy = "sasl",
        mechanism = "PLAIN",
        user = "admin",
        password = "pwd"
      }
      base_config['authentication'] = auth_config
      local ok, err = v(base_config, schema_def)
      assert.is_nil(err)
      assert.is_truthy(ok)
    end)
    it("validates authentication SASL/SCRAM SHA-256", function()
      -- authentication requires 4 entries. constraints apply
      local auth_config = {
        strategy = "sasl",
        mechanism = "SCRAM-SHA-256",
        user = "admin",
        password = "pwd"
      }
      base_config['authentication'] = auth_config
      local ok, err = v(base_config, schema_def)
      assert.is_nil(err)
      assert.is_truthy(ok)
    end)
    it("validates authentication SASL/SCRAM SHA-512", function()
      -- authentication requires 4 entries. constraints apply
      local auth_config = {
        strategy = "sasl",
        mechanism = "SCRAM-SHA-512",
        user = "admin",
        password = "pwd"
      }
      base_config['authentication'] = auth_config
      local ok, err = v(base_config, schema_def)
      assert.is_nil(err)
      assert.is_truthy(ok)
    end)
    it("validates authentication SASL/SCRAM delegation token", function()
      -- authentication requires 4 entries. constraints apply
      local auth_config = {
        strategy = "sasl",
        mechanism = "SCRAM-SHA-256",
        tokenauth = true,
        user = "tokenid",
        password = "hmac"
      }
      base_config['authentication'] = auth_config
      local ok, err = v(base_config, schema_def)
      assert.is_nil(err)
      assert.is_truthy(ok)
    end)
    it("validates authentication faulty#1", function()
      -- mechanism must be 'PLAIN' (all caps)
      local auth_config = {
        strategy = "sasl",
        mechanism = "plain",
        user = "admin",
        password = "pwd"
      }
      base_config['authentication'] = auth_config
      local ok, err = v(base_config, schema_def)
      assert.same({ mechanism = "expected one of: PLAIN, SCRAM-SHA-256, SCRAM-SHA-512" }, err.config.authentication)
      assert.is_not_nil(err)
      assert.is_not_truthy(ok)
    end)
    it("validates authentication faulty#2", function()
      -- strategy must be 'sasl' (all lower)
      local auth_config = {
        strategy = "SASL",
        mechanism = "PLAIN",
        user = "admin",
        password = "pwd"
      }
      base_config['authentication'] = auth_config
      local ok, err = v(base_config, schema_def)
      assert.same({ strategy = "expected one of: sasl" }, err.config.authentication)
      assert.is_not_nil(err)
      assert.is_not_truthy(ok)
    end)
    it("validates authentication faulty#3", function()
      -- username and password must be present
      local auth_config = {
        strategy = "sasl",
        mechanism = "PLAIN",
      }
      base_config['authentication'] = auth_config
      local ok, err = v(base_config, schema_def)
      assert.is_not_nil(err)
      assert.same({ ["@entity"] = { 'if authentication strategy is SASL and mechanism is PLAIN you have to set user and password' } }, err.config)
      assert.is_not_truthy(ok)
    end)
    it("validates authentication faulty#4", function()
      -- username and password must be present
      local auth_config = {
        strategy = "sasl",
        mechanism = "PLAIN",
        user = "foo"
      }
      base_config['authentication'] = auth_config
      local ok, err = v(base_config, schema_def)
      assert.is_not_nil(err)
      assert.same({ ["@entity"] = { 'if authentication strategy is SASL and mechanism is PLAIN you have to set user and password' } }, err.config)
      assert.is_not_truthy(ok)
    end)
    it("validates authentication faulty#4", function()
      -- username and password must be present
      local auth_config = {
        strategy = "sasl",
        mechanism = "PLAIN",
        password = "foo"
      }
      base_config['authentication'] = auth_config
      local ok, err = v(base_config, schema_def)
      assert.is_not_nil(err)
      assert.same({ ["@entity"] = { 'if authentication strategy is SASL and mechanism is PLAIN you have to set user and password' } }, err.config)
      assert.is_not_truthy(ok)
    end)
  end)
  describe("Security schema:", function()
    before_each(function()
      base_config.authentication = {}
    end)

    it("validates certificates", function()
      -- security config can have two settings
      local sec_config = {
        certificate_id = "2daf6392-e62c-11eb-9625-172585559dbe",
        ssl = true,
      }
      base_config['security'] = sec_config
      local ok, err = v(base_config, schema_def)
      assert.is_nil(err)
      assert.is_truthy(ok)
    end)
    it("validates certificates", function()
      -- security config can have two settings
      local sec_config = {
        certificate_id = "2daf6392-e62c-11eb-9625-172585559dbe",
        ssl = true,
      }
      base_config['security'] = sec_config
      local ok, err = v(base_config, schema_def)
      assert.is_nil(err)
      assert.is_truthy(ok)
    end)

    it("validates certificates faulty #1", function()
      -- cert_id is type(uuid)
      local sec_config = {
        certificate_id = "non-uuid-formatted",
      }
      base_config['security'] = sec_config
      local ok, err = v(base_config, schema_def)
      assert.same({ certificate_id = "expected a valid UUID" }, err.config.security)
      assert.is_not_truthy(ok)
    end)

    it("validates certificates faulty #2", function()
      -- ssl is type(bool)
      local sec_config = {
        ssl = 'yes'
      }
      base_config['security'] = sec_config
      local ok, err = v(base_config, schema_def)
      assert.same({ ssl = "expected a boolean" }, err.config.security)
      assert.is_not_truthy(ok)
    end)
  end)
  describe("Producer schema:", function()
    before_each(function()
      base_config.authentication = {}
      base_config.security = {}
    end)

    it("validates producer_request_acks faulty#1", function()
      -- only -1, 0, 1 is valid
      base_config['producer_request_acks'] = 2
      local ok, err = v(base_config, schema_def)
      assert.same("expected one of: -1, 0, 1", err.config.producer_request_acks)
      assert.is_not_truthy(ok)
    end)
  end)
end)
