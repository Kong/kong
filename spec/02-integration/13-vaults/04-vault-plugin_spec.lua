local helpers = require "spec.helpers"
local conf_loader = require "kong.conf_loader"
local Entity = require "kong.db.schema.entity"
local plugins_schema_def = require "kong.db.schema.entities.plugins"

describe("Environment Variables Vault", function()
  local ENV_NAME = "VAULT_ENV_TEST"
  local ENV_VALUE = "The vault value"
  local NORMAL_VALUE = "normal value"
  local VAULT_DIRECTIVE = "{vault://env/vault-env-test}"

  local plugins_schema = assert(Entity.new(plugins_schema_def))

  local schema = {
    name = "test",
    fields = {
      { config = {
          type = "record",
          fields = {
            { field_string = { type = "string", referenceable = true } },
            { field_array = { type = "array", elements = { type = "string", referenceable = true } } },
            { field_set = { type = "set", elements = { type = "string", referenceable = true } } },
            { field_map = { type = "map", keys = { type = "string" }, values = { type = "string", referenceable = true } } },
          },
        }
      }
    }
  }

  local config = {
    field_string = VAULT_DIRECTIVE,
    field_array = {
      VAULT_DIRECTIVE,
      NORMAL_VALUE,
      VAULT_DIRECTIVE,
    },
    field_set = {
      VAULT_DIRECTIVE,
      NORMAL_VALUE,
    },
    field_map = {
      key_1 = NORMAL_VALUE,
      key_2 = VAULT_DIRECTIVE,
    }
  }

  lazy_setup(function()
    local conf = assert(conf_loader(nil, {
      vaults = "bundled",
      plugins = "bundled",
    }))

    local kong_global = require "kong.global"
    _G.kong = kong_global.new()
    kong_global.init_pdk(kong, conf)

    assert(plugins_schema:new_subschema(schema.name, schema))
  end)

  it("should dereference vault value", function()
    finally(function()
      helpers.unsetenv(ENV_NAME)
    end)
    helpers.setenv(ENV_NAME, ENV_VALUE)

    local GLOBAL_QUERY_OPTS = { workspace = ngx.null, show_ws_id = true }
    local entity = plugins_schema:process_auto_fields({
      name = schema.name,
      config = config,
    }, "select", nil, GLOBAL_QUERY_OPTS)

    assert.equal(ENV_VALUE, entity.config.field_string)

    assert.equal(ENV_VALUE, entity.config.field_array[1])
    assert.equal(NORMAL_VALUE, entity.config.field_array[2])
    assert.equal(ENV_VALUE, entity.config.field_array[3])

    assert.equal(ENV_VALUE, entity.config.field_set[1])
    assert.equal(NORMAL_VALUE, entity.config.field_set[2])

    assert.equal(NORMAL_VALUE, entity.config.field_map.key_1)
    assert.equal(ENV_VALUE, entity.config.field_map.key_2)

    -- assert "$refs" content
    assert.equal(VAULT_DIRECTIVE, entity.config["$refs"].field_string)
    assert.same({
      [1] = VAULT_DIRECTIVE,
      [3] = VAULT_DIRECTIVE,
    }, entity.config["$refs"].field_array)
    assert.same({
      VAULT_DIRECTIVE
    }, entity.config["$refs"].field_set)
    assert.same({
      key_2 = VAULT_DIRECTIVE
    }, entity.config["$refs"].field_map)
  end)

end)

