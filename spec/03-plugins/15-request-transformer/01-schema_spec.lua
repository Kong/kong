local schemas = require "kong.dao.schemas_validation"
local request_transformer_schema = require "kong.plugins.request-transformer-advanced.schema"
local validate_entity = schemas.validate_entity

describe("Plugin: request-transformer-advanced(schema)", function()
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
  it("validate regex pattern as value", function()
    local config = {
      add = {
        querystring = {"uri_param1:$(uri_captures.user1)", "uri_param2:$(uri_captures.user2)"},
      }
    }
    local ok, err = validate_entity(config, request_transformer_schema)
    assert.is_true(ok)
    assert.is_nil(err)
  end)
  it("validate string as value", function()
    local config = {
      add = {
        querystring = {"uri_param1:$(uri_captures.user1)", "uri_param2:value"},
      }
    }
    local ok, err = validate_entity(config, request_transformer_schema)
    assert.is_true(ok)
    assert.is_nil(err)
  end)
  it("error for missing value", function()
    local config = {
      add = {
        querystring = {"uri_param2:"},
      }
    }
    local ok, err = validate_entity(config, request_transformer_schema)
    assert.is_false(ok)
    assert.not_nil(err)
  end)
  it("error for malformed regex pattern in value", function()
    local config = {
      add = {
        querystring = {"uri_param2:$(uri_captures user2)"},
      }
    }
    local ok, err = validate_entity(config, request_transformer_schema)
    assert.is_false(ok)
    assert.not_nil(err)
  end)
end)

