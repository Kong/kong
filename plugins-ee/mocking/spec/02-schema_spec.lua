-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local mocking_schema = require "kong.plugins.mocking.schema"
local validate_entity = require("spec.helpers").validate_plugin_config_schema

describe("Plugin: mocking (schema)", function()

  it("accepts a config with only providing api_specification_filename field", function()
    local ok, err = validate_entity({ api_specification_filename = "test.yaml" }, mocking_schema)
    assert.is_nil(err)
    assert.is_truthy(ok)
  end)

  it("accepts a config with only providing api_specification field", function()
    local ok, err = validate_entity({ api_specification = "{}" }, mocking_schema)
    assert.is_nil(err)
    assert.is_truthy(ok)
  end)

  it("rejects if api_specification_filename and api_specification both are empty", function()
    local ok, err = validate_entity({}, mocking_schema)
    assert.is_falsy(ok)
    local expected = {
      "at least one of these fields must be non-empty: 'config.api_specification_filename', 'config.api_specification'"
    }
    assert.is_same(expected, err["@entity"])
  end)

  it("accepts valid json content", function()
    local ok, err = validate_entity({ api_specification = '{"openapi": 3.0.0}' }, mocking_schema)
    assert.is_nil(err)
    assert.is_truthy(ok)
  end)

  it("rejects invalid json content", function()
    local ok, err = validate_entity({ api_specification = "{ invalid" }, mocking_schema)
    assert.is_falsy(ok)
    assert.not_nil(err)
    assert.equal("api specification is neither valid json ('Expected object key string but found invalid token at character 3') nor valid yaml ('2:1: did not find expected ',' or '}'')", err.config.api_specification)
  end)

  it("accepts valid yaml content", function()
    local content = [[
      openapi: 3.0.1
      info:
        title: Simple Inventory API
    ]]
    local ok, err = validate_entity({ api_specification = content }, mocking_schema)
    assert.is_nil(err)
    assert.is_truthy(ok)
  end)

  it("rejects invalid yaml content", function()
    local content = [[
      openapi: 3.0.1
      test
      info:
        title: Simple Inventory API
    ]]
    local ok, err = validate_entity({ api_specification = content }, mocking_schema)
    assert.is_falsy(ok)
    assert.not_nil(err)
    assert.equal("api specification is neither valid json ('Expected value but found invalid token at character 7') nor valid yaml ('1:16: could not find expected ':'')", err.config.api_specification)
  end)

  it("should accept for valid yaml content", function()
    local content = [[
      openapi: 3.0.1
      info:
        title: Simple Inventory API
    ]]
    local ok, err = validate_entity({ api_specification = content }, mocking_schema)
    assert.is_nil(err)
    assert.is_truthy(ok)
  end)

  it("should work with provides all fields", function()
    local config = {
      api_specification_filename = "test.yaml",
      api_specification = "{}",
      random_delay = true,
      min_delay_time = 1.0,
      max_delay_time = 1000.0,
      random_examples = true,
      included_status_codes = { 200, 201, 400, 500 },
      random_status_code = true
    }
    local ok, err = validate_entity(config, mocking_schema)
    assert.is_nil(err)
    assert.is_truthy(ok)
  end)

end)
