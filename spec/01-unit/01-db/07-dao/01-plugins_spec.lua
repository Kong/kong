local Plugins = require("kong.db.dao.plugins")
local Entity = require("kong.db.schema.entity")
local Errors = require("kong.db.errors")
require("spec.helpers") -- add spec/fixtures/custom_plugins to package.path


describe("kong.db.dao.plugins", function()
  local self

  before_each(function()
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

  describe("load_plugin_schemas and get_handlers", function()

    it("loads valid plugin schemas and sets the plugin handlers", function()
      local ok, err = Plugins.load_plugin_schemas(self, {
        ["key-auth"] = true,
        ["basic-auth"] = true,
      })
      assert.is_truthy(ok)
      assert.is_nil(err)

      local handlers, err = Plugins.get_handlers(self)
      assert.is_nil(err)
      assert.is_table(handlers)

      assert.equal("basic-auth", handlers[2].name)
      assert.equal("key-auth", handlers[1].name)

      for i = 1, #handlers do
        assert.is_number(handlers[i].handler.PRIORITY)
        assert.matches("%d%.%d%.%d", handlers[i].handler.VERSION)
        assert.is_function(handlers[i].handler.access)
      end
    end)

    it("fails on invalid plugin schemas", function()
      local ok, err = Plugins.load_plugin_schemas(self, {
        ["key-auth"] = true,
        ["invalid-schema"] = true,
      })

      assert.is_nil(ok)
      assert.match("error loading plugin schemas: on plugin 'invalid-schema'", err, 1, true)

      local handlers, err = Plugins.get_handlers(self)
      assert.is_nil(handlers)
      assert.is_string(err)
    end)

  end)

end)
