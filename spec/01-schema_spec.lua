local validate_entity = require("kong.dao.schemas_validation").validate_entity
local request_validator_schema = require "kong.plugins.request-validator.schema"

describe("request-validator schema", function()
  it("requires a body_schema", function()
    local ok, err = validate_entity({}, request_validator_schema)
    assert.is_false(ok)
    assert.same({body_schema = 'body_schema is required'}, err)
  end)

  it("accepts a valid body_schema", function()
    local ok, err = validate_entity({
      body_schema = '[{"name": {"type": "string"}}]'
    }, request_validator_schema)
    assert.is_true(ok)
    assert.is_nil(err)
  end)

  it("errors with an invalid body_schema json", function()
    local ok, _, err = validate_entity({
      body_schema = '[{"name": {"type": "string}}'
    }, request_validator_schema)
    assert.is_false(ok)
    assert.same("failed decoding schema", err.message)
  end)

  it("errors with an invalid schema", function()
    local ok, _, err = validate_entity({
      body_schema = '[{"name": {"type": "string", "non_existing_field": "bar"}}]'
    }, request_validator_schema)
    assert.is_false(ok)
    assert.same("schema violation", err.name)
  end)

  it("errors with an fields specification", function()
    local ok, _, err = validate_entity({
      body_schema = '{"name": {"type": "string", "non_existing_field": "bar"}}'
    }, request_validator_schema)
    assert.is_false(ok)
    assert.same("schema violation", err.name)
  end)
end)
