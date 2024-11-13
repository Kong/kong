local PLUGIN_NAME = "standard-webhooks"


-- helper function to validate data against a schema
local validate do
  local validate_entity = require("spec.helpers").validate_plugin_config_schema
  local plugin_schema = require("kong.plugins."..PLUGIN_NAME..".schema")

  function validate(data)
    return validate_entity(data, plugin_schema)
  end
end


describe(PLUGIN_NAME .. ": (schema)", function()


  it("accepts a valid config", function()
    local ok, err = validate({
        secret_v1 = "abc123",
        tolerance_second = 5*60,
      })
    assert.is_nil(err)
    assert.is_truthy(ok)
  end)


  describe("secret", function()

    it("must be set", function()
      local ok, err = validate({
        secret_v1 = nil,
        tolerance_second = 5*60,
      })

      assert.is_same({
        ["config"] = {
          ["secret_v1"] = 'required field missing',
        }
      }, err)
      assert.is_falsy(ok)
    end)


    it("is not nullable", function()
      local ok, err = validate({
        secret_v1 = assert(ngx.null),
        tolerance_second = 5*60,
      })

      assert.is_same({
        ["config"] = {
          ["secret_v1"] = 'required field missing',
        }
      }, err)
      assert.is_falsy(ok)
    end)


    it("must be a string", function()
      local ok, err = validate({
        secret_v1 = 123,
        tolerance_second = 5*60,
      })

      assert.is_same({
        ["config"] = {
          ["secret_v1"] = 'expected a string',
        }
      }, err)
      assert.is_falsy(ok)
    end)

  end)



  describe("tolerance_second", function()

    it("gets a default", function()
      local ok, err = validate({
        secret_v1 = "abc123",
        tolerance_second = nil,
      })

      assert.is_nil(err)
      assert.are.same(ok.config, {
        secret_v1 = "abc123",
        tolerance_second = 5*60,
      })
    end)


    it("is not nullable", function()
      local ok, err = validate({
        secret_v1 = "abc123",
        tolerance_second = assert(ngx.null),
      })

      assert.is_same({
        ["config"] = {
          ["tolerance_second"] = 'required field missing',
        }
      }, err)
      assert.is_falsy(ok)
    end)


    it("must be an integer", function()
      local ok, err = validate({
        secret_v1 = "abc123",
        tolerance_second = 5.67,
      })

      assert.is_same({
        ["config"] = {
          ["tolerance_second"] = 'expected an integer',
        }
      }, err)
      assert.is_falsy(ok)
    end)


    it("must be >= 0", function()
      local ok, err = validate({
        secret_v1 = "abc123",
        tolerance_second = -1,
      })

      assert.is_same({
        ["config"] = {
          ["tolerance_second"] = 'value must be greater than -1',
        }
      }, err)
      assert.is_falsy(ok)
    end)

  end)

end)
