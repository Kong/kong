local request_validator_schema = require "kong.plugins.request-validator.schema"
local v = require("spec.helpers").validate_plugin_config_schema


describe("request-validator schema", function()
  it("requires a body_schema", function()
    local ok, err = v({}, request_validator_schema)
    assert.is_nil(ok)
    assert.same("required field missing", err.config.body_schema)
  end)

  describe("[Kong-schema]", function()
    it("accepts a valid body_schema", function()
      local ok, err = v({
        version = "kong",
        body_schema = '[{"name": {"type": "string"}}]'
      }, request_validator_schema)
      assert.is_truthy(ok)
      assert.is_nil(err)
    end)

    it("errors with an invalid body_schema json", function()
      local ok, err = v({
        version = "kong",
        body_schema = '[{"name": {"type": "string}}'
      }, request_validator_schema)
      assert.is_nil(ok)
      assert.same("failed decoding schema: Expected value but found unexpected " ..
                  "end of string at character 29", err["@entity"][1])
    end)

    it("errors with an invalid schema", function()
      local ok, err = v({
        version = "kong",
        body_schema = '[{"name": {"type": "string", "non_existing_field": "bar"}}]'
      }, request_validator_schema)
      assert.is_nil(ok)
      assert.same("schema violation", err["@entity"][1].name)
    end)

    it("errors with an fields specification", function()
      local ok, err = v({
        version = "kong",
        body_schema = '{"name": {"type": "string", "non_existing_field": "bar"}}'
      }, request_validator_schema)
      assert.is_nil(ok)
      assert.same("schema violation", err["@entity"][1].name)
    end)
  end)

  describe("[draft4-schema]", function()
    it("accepts a valid body_schema", function()
      local ok, err = v({
        version = "draft4",
        body_schema = '{"name": {"type": "string"}}'
      }, request_validator_schema)
      assert.is_nil(err)
      assert.is_truthy(ok)
    end)

    it("errors with an invalid body_schema json", function()
      local ok, err = v({
        version = "draft4",
        body_schema = '{"name": {"type": "string}' -- closing bracket missing
      }, request_validator_schema)
      assert.same("failed decoding schema: Expected value but found unexpected " ..
                  "end of string at character 27", err["@entity"][1])
      assert.is_nil(ok)
    end)

    it("errors with an invalid schema", function()
      -- the metaschema references itself, and hence cannot be loaded
      -- to be fixed in ljsonschema lib first
      local ok, err = v({
        version = "draft4",
        body_schema = [[{
            "type": "object",
            "definitions": [ "should have been an object" ]
        }]]
      }, request_validator_schema)
      assert.same("Not a valid JSONschema draft 4 schema: property " ..
        "definitions validation failed: wrong type: " ..
        "expected object, got table", err["@entity"][1])
      assert.is_nil(ok)
    end)
  end)

end)
