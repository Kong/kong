local PLUGIN_NAME = "openid-connect"


local validate do
  local validate_entity = require("spec.helpers").validate_plugin_config_schema
  local plugin_schema = require("kong.plugins."..PLUGIN_NAME..".schema")

  function validate(data)
    return validate_entity(data, plugin_schema)
  end
end


describe(PLUGIN_NAME .. ": (schema)", function()

  it("allows to configure plugin with issuer url", function()
    local ok, err = validate({
        issuer = "https://accounts.google.com/.well-known/openid-configuration",
      })
    assert.is_nil(err)
    assert.is_truthy(ok)
  end)


  it("does not allow configure plugin without issuer url", function()
    local ok, err = validate({
      })
    assert.is_same({
        config = {
          issuer = 'required field missing'
        }
      }, err)
    assert.is_falsy(ok)
  end)

end)
