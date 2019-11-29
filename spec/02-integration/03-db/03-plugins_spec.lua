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
        assert.truthy(ok)
        assert.is_nil(err)

        assert.same("I was implemented for " .. strategy, db.custom_dao:custom_method())
      end)

      it("reports failure with missing plugins", function()
        local ok, err = db.plugins:load_plugin_schemas({
          ["missing"] = true,
        })
        assert.falsy(ok)
        assert.match("missing plugin is enabled but not installed", err, 1, true)
      end)

      it("reports failure with bad plugins #4392", function()
        local ok, err = db.plugins:load_plugin_schemas({
          ["legacy-plugin-bad"] = true,
        })
        assert.falsy(ok)
        assert.match("failed converting legacy schema for legacy-plugin-bad", err, 1, true)
      end)

      it("succeeds with good plugins", function()
        local ok, err = db.plugins:load_plugin_schemas({
          ["legacy-plugin-good"] = true,
        })
        assert.truthy(ok)
        assert.is_nil(err)

        local foo = {
          required = false,
          type = "map",
          keys = { type = "string" },
          values = { type = "string" },
          default = {
            foo = "boo",
            bar = "bla",
          }
        }
        local config = {
          type = "record",
          required = true,
          fields = {
            { foo = foo },
            foo = foo,
          }
        }
        local consumer = {
          type = "foreign",
          reference = "consumers",
          eq = ngx.null,
          schema = db.consumers.schema,
        }
        assert.same({
          name = "legacy-plugin-good",
          fields = {
            { config = config },
            { consumer = consumer },
            config = config,
            consumer = consumer,
          }
        }, db.plugins.schema.subschemas["legacy-plugin-good"])
      end)
    end)
  end) -- kong.db [strategy]
end
