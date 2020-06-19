local singletons = require "kong.singletons"
local ee_invoke_plugin = require "kong.enterprise_edition.invoke_plugin"

describe("ee invoke_plugin", function()
  local loaded_plugins = {
    {
      handler = {
        _name = "cors"
      },
      name = "cors"
    },
  }

  local kong_global = {
    set_phase = function() end,
    set_named_ctx = function() end,
    phases = {
      init_worker = 1,
      rewrite = 16,
      access = 32,
      balancer = 64,
      header_filter = 512,
      body_filter = 1024,
      admin_api = 268435456,
    },
  }

  setup(function()
    singletons.configuration = {}
  end)

  before_each(function()
    singletons.db = {
      plugins = {
        schema = {
          validate_insert = function () return true end,
        },
      },
    }
  end)

  after_each(function()
    singletons.configuration = {}
  end)

  teardown(function()
    singletons = nil -- luacheck: ignore
  end)

  describe("new()", function()
    it("should start succesfully", function()
      local instance = ee_invoke_plugin.new({
        loaded_plugins = loaded_plugins,
        kong_global = kong_global,
      })

      assert.truthy(instance)
    end)
  end)

  describe("prepare_plugin", function()
    it("prepares plugins and returns config, handler", function ()
      local instance = ee_invoke_plugin.new({
        loaded_plugins = loaded_plugins,
        kong_global = kong_global,
      })

      singletons.db.plugins.schema.process_auto_fields = function () return
        { name = "cors", config = { credentials = true, } }
      end

      local ok, err = instance.prepare_plugin({
        name = "cors",
        config = {},
        phases = { "access" },
        db = singletons.db,
      })

      assert.truthy(ok)
      assert.falsy(err)
      assert.equal(true, ok.config.credentials)
      assert.same(loaded_plugins[1].handler, ok.handler)
    end)

    it("invoke - strips out cors default ports", function()
      local origins = {
        "https://example.com:443",
        "http://example.com:80",
        "http://hey.com:8080",
        "https://hey.com:4443",
        "http://hey.com:4434",
      }

      local instance = ee_invoke_plugin.new({
        loaded_plugins = loaded_plugins,
        kong_global = kong_global,
      })

      singletons.db.plugins.schema.process_auto_fields = function () return {
        name = "cors", config = { origins = origins },
      } end

      local ok, err = instance.prepare_plugin({
        name = "cors",
        config = {
          origins = origins
        },
        phases = { "access", "header_filter" },
        db = singletons.db,
      })

      assert.truthy(ok)
      assert.falsy(err)
      assert.same({
        "https://example.com",
        "http://example.com",
        "http://hey.com:8080",
        "https://hey.com:4443",
        "http://hey.com:4434",
      }, ok.config.origins)
    end)
  end)
end)
