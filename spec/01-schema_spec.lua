local request_validator_schema = require "kong.plugins.request-validator.schema"
local v = require("spec.helpers").validate_plugin_config_schema


describe("request-validator schema", function()
  it("requires a body_schema", function()
    local ok, err = v({}, request_validator_schema)
    assert.is_nil(ok)
    assert.same("required field missing", err.config.body_schema)
  end)

  it("accepts a valid body_schema", function()
    local ok, err = v({
      body_schema = '[{"name": {"type": "string"}}]'
    }, request_validator_schema)
    assert.is_truthy(ok)
    assert.is_nil(err)
  end)

  it("errors with an invalid body_schema json", function()
    local ok, err = v({
      body_schema = '[{"name": {"type": "string}}'
    }, request_validator_schema)
    assert.is_nil(ok)
    assert.same("failed decoding schema", err["@entity"][1])
  end)

  it("errors with an invalid schema", function()
    local ok, err = v({
      body_schema = '[{"name": {"type": "string", "non_existing_field": "bar"}}]'
    }, request_validator_schema)
    assert.is_nil(ok)
    assert.same("schema violation", err["@entity"][1].name)
  end)

  it("errors with an fields specification", function()
    local ok, err = v({
      body_schema = '{"name": {"type": "string", "non_existing_field": "bar"}}'
    }, request_validator_schema)
    assert.is_nil(ok)
    assert.same("schema violation", err["@entity"][1].name)
  end)
end)
