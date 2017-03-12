local schemas = require "kong.dao.schemas_validation"
local request_transformer_schema = require "kong.plugins.request-transformer.schema"
local validate_entity = schemas.validate_entity

describe("Plugin: request-transformer (schema)", function()
  it("validates http_method", function()
    local ok, err = validate_entity({http_method = "GET"}, request_transformer_schema)
    assert.is_nil(err)
    assert.True(ok)
  end)
  it("errors invalid http_method", function()
    local ok, err = validate_entity({http_method = "HELLO"}, request_transformer_schema)
    assert.equal("HELLO is not supported", err.http_method)
    assert.False(ok)
  end)
end)
