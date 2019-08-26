local plugin_name = "route-transformer-advanced"

local route_transformer_schema = require("kong.plugins." .. plugin_name .. ".schema")
local validate = require("spec.helpers").validate_plugin_config_schema

local function validate_schema(config)
  return validate(config, route_transformer_schema)
end

describe("Plugin: " .. plugin_name .. "(schema)", function()

  it("validates config.path", function()
    local ok, err = validate_schema { path = "/my/path" }
    assert.truthy(ok)
    assert.falsy(err)

    ok, err = validate_schema { path = "$(shared.custom_path)" }
    assert.truthy(ok)
    assert.falsy(err)

    ok, err = validate_schema { path = "$(this does not work)" }
    assert.same({
      config = {
        path = [[value '$(this does not work)' is not in supported format, error:[string "TMP"]:4: ')' expected near 'does']]
      }
    }, err)
    assert.falsy(ok)
  end)


  it("validates config.port", function()
    local ok, err = validate_schema { port = "1234" }
    assert.truthy(ok)
    assert.falsy(err)

    ok, err = validate_schema { port = "$(shared.custom_port)" }
    assert.truthy(ok)
    assert.falsy(err)

    ok, err = validate_schema { port = "$(this does not work)" }
    assert.same({
      config = {
        port = [[value '$(this does not work)' is not in supported format, error:[string "TMP"]:4: ')' expected near 'does']]
      }
    }, err)
    assert.falsy(ok)
  end)


  it("validates config.host", function()
    local ok, err = validate_schema { host = "mycompany.com" }
    assert.truthy(ok)
    assert.falsy(err)

    ok, err = validate_schema { host = "$(shared.custom_host)" }
    assert.truthy(ok)
    assert.falsy(err)

    ok, err = validate_schema { host = "$(this does not work)" }
    assert.same({
      config = {
        host = [[value '$(this does not work)' is not in supported format, error:[string "TMP"]:4: ')' expected near 'does']]
      }
    }, err)
    assert.falsy(ok)
  end)


  it("at least one of host, port or path must be provided", function()
    local ok, err = validate_schema {}
    assert.same({
      config = {
        ["@entity"] = { [[at least one of these fields must be non-empty: 'path', 'port', 'host']] }
      }
    }, err)
    assert.falsy(ok)
  end)

end)

