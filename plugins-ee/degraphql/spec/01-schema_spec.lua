-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local degraphql_schema = require "kong.plugins.degraphql.schema"
local helpers = require "spec.helpers"
local validate_plugin_config_schema = helpers.validate_plugin_config_schema

describe("degraphql schema", function()

  it("accepts a minimal config", function()
    local entity, err = validate_plugin_config_schema({
    }, degraphql_schema)

    assert.is_nil(err)
    assert.is_truthy(entity)
  end)

  it("accepts graphql server path parameter", function()
    local entity, err = validate_plugin_config_schema({
      graphql_server_path = "/v1/graphql",
    }, degraphql_schema)

    assert.is_nil(err)
    assert.is_truthy(entity)
  end)

  it("doesn't accept bad graphql server path", function()
    local entity, err = validate_plugin_config_schema({
      graphql_server_path = "bad path",
    }, degraphql_schema)

    assert.matches("^should start with", err.config.graphql_server_path)
    assert.is_falsy(entity)
  end)

end)
