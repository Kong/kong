local Plugins = require("kong.db.dao.plugins")
local Entity = require("kong.db.schema.entity")
local Errors = require("kong.db.errors")
require("spec.helpers") -- add spec/fixtures/custom_plugins to package.path


describe("kong.db.dao.plugins", function()
  local self

  lazy_setup(function()
    assert(Entity.new(require("kong.db.schema.entities.services")))
    assert(Entity.new(require("kong.db.schema.entities.routes")))
    assert(Entity.new(require("kong.db.schema.entities.consumers")))
    local schema = assert(Entity.new(require("kong.db.schema.entities.plugins")))

    local errors = Errors.new("mock")
    self = {
      schema = schema,
      errors = errors,
      db = {
        errors = errors,
      },
    }
  end)

  describe("load_plugin_schemas", function()

    it("loads valid plugin schemas", function()
      local schemas, err = Plugins.load_plugin_schemas(self, {
        ["key-auth"] = true,
        ["basic-auth"] = true,
      })
      assert.is_nil(err)

      table.sort(schemas, function(a, b)
        return a.name < b.name
      end)

      assert.same({
        {
          handler = { _name = "basic-auth" },
          name = "basic-auth",
        },
        {
          handler = { _name = "key-auth" },
          name = "key-auth",
        },
      }, schemas)
    end)

    it("fails on invalid plugin schemas", function()
      local schemas, err = Plugins.load_plugin_schemas(self, {
        ["key-auth"] = true,
        ["invalid-schema"] = true,
      })

      assert.is_nil(schemas)
      assert.match("error loading plugin schemas: on plugin 'invalid-schema'", err, 1, true)
    end)

  end)

end)
