local helpers = require "spec.helpers"


assert:set_parameter("TableFormatLevel", 10)


local UUID_PATTERN = "%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x"


for _, strategy in helpers.each_strategy() do
  describe("kong.db [#" .. strategy .. "]", function()
    local db, bp, service, route
    local global_plugin

    lazy_setup(function()
      bp, db = helpers.get_db_utils(strategy, {
        "routes",
        "services",
        "plugins",
      })

      global_plugin = db.plugins:insert({ name = "key-auth",
                                          protocols = { "http" },
                                        })
      assert.truthy(global_plugin)

    end)

    describe("Plugins #plugins", function()

      before_each(function()
        service = bp.services:insert()
        route = bp.routes:insert({ service = { id = service.id },
                                   protocols = { "tcp" },
                                   sources = { { ip = "127.0.0.1" } },
                                 })
      end)

      describe(":insert()", function()
        it("checks composite uniqueness", function()
          local route = bp.routes:insert({ methods = {"GET"} })

          local plugin, err, err_t = db.plugins:insert({
            name = "key-auth",
            route = { id = route.id },
          })
          assert.is_nil(err_t)
          assert.is_nil(err)

          assert.matches(UUID_PATTERN, plugin.id)
          assert.is_number(plugin.created_at)
          plugin.id = nil
          plugin.created_at = nil

          assert.same({
            config = {
              hide_credentials = false,
              run_on_preflight = true,
              key_in_header = true,
              key_in_query = true,
              key_in_body = false,
              key_names = { "apikey" },
            },
            protocols = { "grpc", "grpcs", "http", "https" },
            enabled = true,
            name = "key-auth",
            route = {
              id = route.id,
            },
          }, plugin)

          plugin, err, err_t = db.plugins:insert({
            name = "key-auth",
            route = route,
          })

          assert.falsy(plugin)
          assert.match("UNIQUE violation", err)
          assert.same("unique constraint violation", err_t.name)
          assert.same([[UNIQUE violation detected on '{consumer=null,name="key-auth",]] ..
                      [[route={id="]] .. route.id ..
                      [["},service=null}']], err_t.message)
        end)

        it("does not validate when associated to an incompatible route, or a service with only incompatible routes", function()
          local plugin, _, err_t = db.plugins:insert({ name = "key-auth",
                                                       protocols = { "http" },
                                                       route = { id = route.id },
                                                     })
          assert.is_nil(plugin)
          assert.equals(err_t.fields.protocols, "must match the associated route's protocols")

          local plugin, _, err_t = db.plugins:insert({ name = "key-auth",
                                                       protocols = { "http" },
                                                       service = { id = service.id },
                                                     })
          assert.is_nil(plugin)
          assert.equals(err_t.fields.protocols,
                        "must match the protocols of at least one route pointing to this Plugin's service")
        end)

        it("validates when associated to a service with no routes", function()
          local service_with_no_routes = bp.services:insert()
          local plugin, _, err_t = db.plugins:insert({ name = "key-auth",
                                                       protocols = { "http" },
                                                       service = { id = service_with_no_routes.id },
                                                     })
          assert.truthy(plugin)
          assert.is_nil(err_t)
        end)
      end)

      describe(":update()", function()
        it("checks composite uniqueness", function()
          local route = bp.routes:insert({ methods = {"GET"} })

          local plugin, err, err_t = db.plugins:insert({
            name = "key-auth",
            route = { id = route.id },
          })
          assert.is_nil(err_t)
          assert.is_nil(err)

          assert.matches(UUID_PATTERN, plugin.id)
          assert.is_number(plugin.created_at)
          plugin.id = nil
          plugin.created_at = nil

          assert.same({
            config = {
              hide_credentials = false,
              run_on_preflight = true,
              key_in_header = true,
              key_in_query = true,
              key_in_body = false,
              key_names = { "apikey" },
            },
            protocols = { "grpc", "grpcs", "http", "https" },
            enabled = true,
            name = "key-auth",
            route = {
              id = route.id,
            },
          }, plugin)

          plugin, err, err_t = db.plugins:insert({
            name = "key-auth",
            route = route,
          })

          assert.falsy(plugin)
          assert.match("UNIQUE violation", err)
          assert.same("unique constraint violation", err_t.name)
          assert.same([[UNIQUE violation detected on '{consumer=null,name="key-auth",]] ..
                      [[route={id="]] .. route.id ..
                      [["},service=null}']], err_t.message)
        end)
      end)

      it("returns an error when updating mismatched plugins", function()
        local p, _, err_t = db.plugins:update({ id = global_plugin.id },
                                              { route = { id = route.id } })
        assert.is_nil(p)
        assert.equals(err_t.fields.protocols, "must match the associated route's protocols")


        local p, _, err_t = db.plugins:update({ id = global_plugin.id },
                                              { service = { id = service.id } })
        assert.is_nil(p)
        assert.equals(err_t.fields.protocols,
                      "must match the protocols of at least one route pointing to this Plugin's service")
      end)
    end)

    describe(":upsert()", function()
      it("returns an error when upserting mismatched plugins", function()
        local p, _, err_t = db.plugins:upsert({ id = global_plugin.id },
                                              { route = { id = route.id }, protocols = { "http" } })
        assert.is_nil(p)
        assert.equals(err_t.fields.protocols, "must match the associated route's protocols")


        local p, _, err_t = db.plugins:upsert({ id = global_plugin.id },
                                              { service = { id = service.id }, protocols = { "http" } })
        assert.is_nil(p)
        assert.equals(err_t.fields.protocols,
                      "must match the protocols of at least one route pointing to this Plugin's service")
      end)
    end)

    describe(":load_plugin_schemas()", function()
      it("loads custom entities with specialized methods", function()
        local ok, err = db.plugins:load_plugin_schemas({
          ["plugin-with-custom-dao"] = true,
        })
        assert.is_nil(err)
        assert.truthy(ok)

        assert.same("I was implemented for " .. strategy, db.custom_dao:custom_method())
      end)

      it("reports failure with missing plugins", function()
        local ok, err = db.plugins:load_plugin_schemas({
          ["missing"] = true,
        })
        assert.falsy(ok)
        assert.match("missing plugin is enabled but not installed", err, 1, true)
      end)

      describe("with bad PRIORITY fails; ", function()
        setup(function()
          local schema = {}
          package.loaded["kong.plugins.NaN_priority.schema"] = schema
          package.loaded["kong.plugins.NaN_priority.handler"] = { PRIORITY = 0/0, VERSION = "1.0" }
          package.loaded["kong.plugins.huge_negative.schema"] = schema
          package.loaded["kong.plugins.huge_negative.handler"] = { PRIORITY = -math.huge, VERSION = "1.0" }
          package.loaded["kong.plugins.string_priority.schema"] = schema
          package.loaded["kong.plugins.string_priority.handler"] = { PRIORITY = "abc", VERSION = "1.0" }
        end)

        teardown(function()
          package.loaded["kong.plugins.NaN_priority.schema"] = nil
          package.loaded["kong.plugins.NaN_priority.handler"] = nil
          package.loaded["kong.plugins.huge_negative.schema"] = nil
          package.loaded["kong.plugins.huge_negative.handler"] = nil
          package.loaded["kong.plugins.string_priority.schema"] = nil
          package.loaded["kong.plugins.string_priority.handler"] = nil
        end)

        it("NaN", function()
          local ok, err = db.plugins:load_plugin_schemas({
            ["NaN_priority"] = true,
          })
          assert.falsy(ok)
          assert.match('Plugin "NaN_priority" cannot be loaded because its PRIORITY field is not a valid integer number, got: "nan"', err, 1, true)
        end)

        it("-math.huge", function()
          local ok, err = db.plugins:load_plugin_schemas({
            ["huge_negative"] = true,
          })
          assert.falsy(ok)
          assert.match('Plugin "huge_negative" cannot be loaded because its PRIORITY field is not a valid integer number, got: "-inf"', err, 1, true)
        end)

        it("string", function()
          local ok, err = db.plugins:load_plugin_schemas({
            ["string_priority"] = true,
          })
          assert.falsy(ok)
          assert.match('Plugin "string_priority" cannot be loaded because its PRIORITY field is not a valid integer number, got: "abc"', err, 1, true)
        end)

      end)

      describe("with bad VERSION fails; ", function()
        setup(function()
          local schema = {}
          package.loaded["kong.plugins.no_version.schema"] = schema
          package.loaded["kong.plugins.no_version.handler"] = { PRIORITY = 1000, VERSION = nil }
          package.loaded["kong.plugins.too_many.schema"] = schema
          package.loaded["kong.plugins.too_many.handler"] = { PRIORITY = 1000, VERSION = "1.0.0.0" }
          package.loaded["kong.plugins.number.schema"] = schema
          package.loaded["kong.plugins.number.handler"] = { PRIORITY = 1000, VERSION = 123 }
        end)

        teardown(function()
          package.loaded["kong.plugins.no_version.schema"] = nil
          package.loaded["kong.plugins.no_version.handler"] = nil
          package.loaded["kong.plugins.too_many.schema"] = nil
          package.loaded["kong.plugins.too_many.handler"] = nil
          package.loaded["kong.plugins.number.schema"] = nil
          package.loaded["kong.plugins.number.handler"] = nil
        end)

        it("without version", function()
          local ok, err = db.plugins:load_plugin_schemas({
            ["no_version"] = true,
          })
          assert.falsy(ok)
          assert.match('Plugin "no_version" cannot be loaded because its VERSION field does not follow the "x.y.z" format, got: "nil"', err, 1, true)
        end)

        it("too many components", function()
          local ok, err = db.plugins:load_plugin_schemas({
            ["too_many"] = true,
          })
          assert.falsy(ok)
          assert.match('Plugin "too_many" cannot be loaded because its VERSION field does not follow the "x.y.z" format, got: "1.0.0.0"', err, 1, true)
        end)

        it("number", function()
          local ok, err = db.plugins:load_plugin_schemas({
            ["number"] = true,
          })
          assert.falsy(ok)
          assert.match('Plugin "number" cannot be loaded because its VERSION field does not follow the "x.y.z" format, got: "123"', err, 1, true)
        end)

      end)

    end)

  end) -- kong.db [strategy]

end
