local PLUGIN_NAME = "http-log"


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
        http_endpoint = "http://myservice.com/path",
      })
    assert.is_nil(err)
    assert.is_truthy(ok)
  end)


  it("does accept allowed headers", function()
    local ok, err = validate({
        http_endpoint = "http://myservice.com/path",
        headers = {
          ["X-My-Header"] = { "123" }
        }
      })
    assert.is_nil(err)
    assert.is_truthy(ok)
  end)


  it("does not accept Host header", function()
    local ok, err = validate({
        http_endpoint = "http://myservice.com/path",
        headers = {
          Host = { "MyHost" }
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
        http_endpoint = "http://myservice.com/path",
        headers = {
          ["coNTEnt-Length"] = { "123" }  -- also validate casing
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
        http_endpoint = "http://myservice.com/path",
        headers = {
          ["coNTEnt-Type"] = { "bad" }  -- also validate casing
        }
      })
      assert.same({
        config = {
          headers = "cannot contain 'Content-Type' header"
        } }, err)
      assert.is_falsy(ok)
    end)


    it("does not accept userinfo in URL and 'Authorization' header", function()
      local ok, err = validate({
          http_endpoint = "http://hi:there@myservice.com/path",
          headers = {
            ["AuthoRIZATion"] = { "bad" }  -- also validate casing
          }
        })
        assert.same({
            config = "specifying both an 'Authorization' header and user info in 'http_endpoint' is not allowed"
          }, err)
        assert.is_falsy(ok)
      end)


  end)
