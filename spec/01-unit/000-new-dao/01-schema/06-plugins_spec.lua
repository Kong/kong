local Schema = require "kong.db.schema"
local typedefs = require "kong.db.schema.typedefs"
local utils = require "kong.tools.utils"
local plugins_definition = require "kong.db.schema.entities.plugins"
local dao_plugins = require "kong.db.dao.plugins"


describe("plugins", function()
  local Plugins
  local db

  setup(function()
    Plugins = Schema.new(plugins_definition)

    local my_plugins = {
      "key-auth",
      "rate-limiting",
      "response-transformer",
      "request-transformer",
    }

    local loaded_plugins = {}
    for _, v in ipairs(my_plugins) do
      loaded_plugins[v] = true
    end

    local kong_conf = {
      anonymous_reports = false,
      loaded_plugins = loaded_plugins,
    }

    db = {
      plugins = {
        schema = Plugins,
        each = function()
          local i = 0
          return function()
            i = i + 1
            if my_plugins[i] then
              return { name = my_plugins[i] }
            end
          end
        end,
      },
    }

    assert(dao_plugins.load_plugin_schemas({
      db = db.plugins,
      schema = Plugins,
    }, kong_conf.loaded_plugins))
  end)

  it("has a cache_key", function()
    assert.is_table(Plugins.cache_key)
  end)

  it("should not validate if the plugin doesn't exist (not installed)", function()
    local plugin = {
      name = "world domination"
    }
    plugin = Plugins:process_auto_fields(plugin)
    local valid, err = Plugins:validate(plugin)
    assert.falsy(valid)
    assert.equal("plugin 'world domination' not enabled; add it to the 'plugins' configuration property", err.name)
  end)

  it("should validate a plugin configuration's `config` field", function()
    -- Success
    local plugin = {
      name = "key-auth",
      service = { id = utils.uuid() },
      config = {
        key_names = { "x-kong-key" }
      }
    }
    plugin = Plugins:process_auto_fields(plugin)
    local valid, err = Plugins:validate(plugin)
    assert.same(nil, err)
    assert.is_true(valid)

    -- Failure
    plugin = {
      name = "rate-limiting",
      service = { id = utils.uuid() },
      config = {
        second = "hello"
      }
    }

    plugin = Plugins:process_auto_fields(plugin)
    local errors
    valid, errors = Plugins:validate(plugin)
    assert.falsy(valid)
    assert.same({
      config = {
        second = "expected a number"
      }
    }, errors)
  end)

  it("should have an empty config if none is specified and if the config schema does not have default", function()
    -- Insert key-auth, whose config has some default values that should be set
    local plugin = {
      name = "key-auth",
      service = { id = utils.uuid() },
    }
    plugin = Plugins:process_auto_fields(plugin)
    local ok = Plugins:validate(plugin)
    assert.is_true(ok)
    assert.same({
      key_names = { "apikey" },
      hide_credentials = false,
      anonymous = "",
      key_in_body = false,
      run_on_preflight = true,
    }, plugin.config)
  end)

  it("should be valid if no value is specified for a subfield and if the config schema has default as empty array", function()
    -- Insert response-transformer, whose default config has no default values, and should be empty
    local plugin = {
      name = "response-transformer",
      service = { id = utils.uuid() },
    }
    plugin = Plugins:process_auto_fields(plugin)
    local ok = Plugins:validate(plugin)
    assert.is_true(ok)
    assert.same({
      remove = {
        headers = {},
        json = {}
      },
      replace = {
        headers = {},
        json = {}
      },
      add = {
        headers = {},
        json = {}
      },
      append = {
        headers = {},
        json = {}
      }
    }, plugin.config)
  end)

  describe("should refuse if criteria in plugin schema not met", function()
    it("no_api", function()
      local subschema = {
        name = "with-no-api",
        fields = {
          { api = typedefs.no_api },
          { config = {
              type = "record",
              fields = {
                { string = { type = "string", required = true } },
              }
          } }
        }
      }
      assert(db.plugins.schema:new_subschema(subschema.name, subschema))

      local ok, err = Plugins:validate(Plugins:process_auto_fields({
        name = "with-no-api",
        api = { id = utils.uuid() },
        config = {
          string = "foo",
        }
      }))
      assert.falsy(ok)
      assert.same({
        api = "value must be null"
      }, err)

      ok = Plugins:validate(Plugins:process_auto_fields({
        name = "with-no-api",
        api = ngx.null,
        config = {
          string = "foo",
        }
      }))
      assert.truthy(ok)
    end)

    it("no_route", function()
      local subschema = {
        name = "with-no-route",
        fields = {
          { route = typedefs.no_route },
          { config = {
              type = "record",
              fields = {
                { string = { type = "string", required = true } },
              }
          } }
        }
      }
      assert(db.plugins.schema:new_subschema(subschema.name, subschema))

      local ok, err = Plugins:validate(Plugins:process_auto_fields({
        name = "with-no-route",
        route = { id = utils.uuid() },
        config = {
          string = "foo",
        }
      }))
      assert.falsy(ok)
      assert.same({
        route = "value must be null",
      }, err)

      ok = Plugins:validate(Plugins:process_auto_fields({
        name = "with-no-route",
        route = ngx.null,
        config = {
          string = "foo",
        }
      }))
      assert.truthy(ok)
    end)

    it("no_service", function()
      local subschema = {
        name = "with-no-service",
        fields = {
          { service = typedefs.no_service },
          { config = {
              type = "record",
              fields = {
                { string = { type = "string", required = true } },
              }
          } }
        }
      }
      assert(db.plugins.schema:new_subschema(subschema.name, subschema))

      local ok, err = Plugins:validate(Plugins:process_auto_fields({
        name = "with-no-service",
        service = { id = utils.uuid() },
        config = {
          string = "foo",
        }
      }))
      assert.falsy(ok)
      assert.same({
        service = "value must be null",
      }, err)

      ok = Plugins:validate(Plugins:process_auto_fields({
        name = "with-no-service",
        service = ngx.null,
        config = {
          string = "foo",
        }
      }))
      assert.truthy(ok)
    end)

    it("no_consumer", function()
      local subschema = {
        name = "with-no-consumer",
        fields = {
          { consumer = typedefs.no_consumer },
          { config = {
              type = "record",
              fields = {
                { string = { type = "string", required = true } },
              }
          } }
        }
      }
      assert(db.plugins.schema:new_subschema(subschema.name, subschema))

      local ok, err = Plugins:validate(Plugins:process_auto_fields({
        name = "with-no-consumer",
        consumer = { id = utils.uuid() },
        config = {
          string = "foo",
        }
      }))
      assert.falsy(ok)
      assert.same({
        consumer = "value must be null",
      }, err)

      ok = Plugins:validate(Plugins:process_auto_fields({
        name = "with-no-consumer",
        consumer = ngx.null,
        config = {
          string = "foo",
        }
      }))
      assert.truthy(ok)
    end)

    it("rejects a plugin if configured for both api and route", function()
      local ok, err = Plugins:validate(Plugins:process_auto_fields({
        name = "request-transformer",
        api = { id = utils.uuid() },
        route = { id = utils.uuid() },
      }))
      assert.falsy(ok)
      assert.same({
        ["@entity"] = {
          "failed conditional validation given value of field 'api'"
        },
        route = "value must be null",
      }, err)
    end)

    it("rejects a plugin if configured for both api and service", function()
      local ok, err = Plugins:validate(Plugins:process_auto_fields({
        name = "request-transformer",
        api = { id = utils.uuid() },
        service = { id = utils.uuid() },
      }))
      assert.falsy(ok)
      assert.same({
        ["@entity"] = {
          "failed conditional validation given value of field 'api'"
        },
        service = "value must be null",
      }, err)
    end)

    it("accepts a plugin if configured for api", function()
      assert(Plugins:validate(Plugins:process_auto_fields({
        name = "key-auth",
        api = { id = utils.uuid() },
      })))
    end)

    it("accepts a plugin if configured for route", function()
      assert(Plugins:validate(Plugins:process_auto_fields({
        name = "key-auth",
        route = { id = utils.uuid() },
      })))
    end)

    it("accepts a plugin if configured for service", function()
      assert(Plugins:validate(Plugins:process_auto_fields({
        name = "key-auth",
        service = { id = utils.uuid() },
      })))
    end)

    it("accepts a plugin if configured for consumer", function()
      assert(Plugins:validate(Plugins:process_auto_fields({
        name = "rate-limiting",
        consumer = { id = utils.uuid() },
        config = {
          second = 1,
        }
      })))
    end)
  end)

end)
