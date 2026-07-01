local helpers = require "spec.helpers"
local Entity = require "kong.db.schema.entity"
local plugins_schema_def = require "kong.db.schema.entities.plugins"
local conf_loader = require "kong.conf_loader"

local PLUGIN_NAME = "jwt"


describe(PLUGIN_NAME .. ": (schema-vault)", function()
  local plugins_schema = assert(Entity.new(plugins_schema_def))

  lazy_setup(function()
    local conf = assert(conf_loader(nil, {
      vaults = "bundled",
      plugins = "bundled",
    }))

    local kong_global = require "kong.global"
    _G.kong = kong_global.new()
    kong_global.init_pdk(kong, conf)

    local plugin_schema = require("kong.plugins."..PLUGIN_NAME..".schema")
    assert(plugins_schema:new_subschema(PLUGIN_NAME, plugin_schema))
  end)

  it("should dereference vault value", function()
    local env_name = "JWT_SECRET_IS_BASE64"
    local env_value = "true"

    finally(function()
      helpers.unsetenv(env_name)
    end)

    helpers.setenv(env_name, env_value)

    local entity = plugins_schema:process_auto_fields({
      name = PLUGIN_NAME,
      config = {
        secret_is_base64 = "{vault://env/jwt-secret-is-base64}"
      },
    }, "select")

    assert.equal(env_value, entity.config.secret_is_base64)
  end)
end)
