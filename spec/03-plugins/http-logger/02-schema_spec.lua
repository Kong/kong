local PLUGIN_NAME = "http-logger"

-- helper function to validate data against a schema
local validate do
  local validate_entity = require("spec.helpers").validate_plugin_config_schema
  local plugin_schema = require("kong.plugins."..PLUGIN_NAME..".schema")

  function validate(data)
    return validate_entity(data, plugin_schema)
  end
end

describe(PLUGIN_NAME .. ": (schema)", function()
  it("accepts minimal config with defaults", function()
    local ok, err = validate({
        http_endpoint = "http://myservice.test/path",
      })
    assert.is_nil(err)
    assert.is_truthy(ok)
  end)

  it("accepts empty headers with username/password in the http_endpoint", function()
    local ok, err = validate({
        http_endpoint = "http://bob:password@myservice.test/path",
      })
    assert.is_nil(err)
    assert.is_truthy(ok)
  end)

  it("does not accept Host header", function()
    local ok, err = validate({
        http_endpoint = "http://myservice.test/path",
        headers = {
          ["X-My-Header"] = "123",
          Host = "MyHost",
        }
      })
      assert.same({
        config = {
          headers = "cannot contain 'Host' header"
        } }, err)
      assert.is_falsy(ok)
    end)
    
  it("does not accept Content-Length header", function()
    local ok, err = validate({
        http_endpoint = "http://myservice.test/path",
        headers = {
          ["Content-Length"] = "123",
        }
      })
      assert.same({
        config = {
          headers = "cannot contain 'Content-Length' header"
        } }, err)
      assert.is_falsy(ok)
  end)
  
  it("does not accept Content-Type header", function()
    local ok, err = validate({
        http_endpoint = "http://myservice.test/path",
        headers = {
          ["Content-Type"] = "application/json",
        }
      })
      assert.same({
        config = {
          headers = "cannot contain 'Content-Type' header"
        } }, err)
      assert.is_falsy(ok)
  end)
  
  it("does not accept userinfo in endpoint and Authorization header", function()
    local ok, err = validate({
        http_endpoint = "http://user:pass@myservice.test/path",
        headers = {
          ["Authorization"] = "Basic dXNlcjpwYXNz",
        }
      })
      assert.same(
        "specifying both an 'Authorization' header and user info in 'http_endpoint' is not allowed",
        err.config)
      assert.is_falsy(ok)
  end)
end)
