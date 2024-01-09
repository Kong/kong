-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local plugin_name = "oas-validation"

local validation_schema = require "kong.plugins.oas-validation.schema"
local v = require("spec.helpers").validate_plugin_config_schema
local helpers = require "spec.helpers"

describe("Plugin: " .. plugin_name .. "(schema)", function()

    it("requires api spec", function()
      local ok, err = v({}, validation_schema)
      assert.is_nil(ok)
      assert.same("required field missing", err.config["api_spec"])
    end)


    it("accepts a valid json api_spec", function()
        local ok, err = v({
            api_spec = assert(io.open(helpers.get_fixtures_path() .. "/resources/petstore-swagger.json"):read("*a")),
        }, validation_schema)
        assert.is_truthy(ok)
        assert.is_nil(err)
    end)

    it("accepts a valid yaml api_spec", function()
        local ok, err = v({
            api_spec = assert(io.open(helpers.get_fixtures_path() .. "/resources/xero-finance-oas.yaml"):read("*a")),
        }, validation_schema)
        assert.is_truthy(ok)
        assert.is_nil(err)
    end)

    it("errors with invalid json api_spec", function()
        local ok, err = v({
            api_spec = '[{"name": {"type": "string}}',
        }, validation_schema)
        assert.is_nil(ok)
        assert.same("api specification is neither valid json ('Expected value " ..
            "but found unexpected end of string at character 29') nor " ..
            "valid yaml ('1:1: found unexpected end of stream')", err.config["api_spec"])
    end)

    it("errors with invalid yaml api_spec", function()
        local ok, err = v({
            api_spec = "not a valid yaml spec",
        }, validation_schema)
        assert.is_nil(ok)
        assert.same("api specification is neither valid json ('Expected value " ..
            "but found invalid token at character 1') nor valid yaml ('not " ..
            "a valid yaml spec')", err.config["api_spec"])
    end)

end)
