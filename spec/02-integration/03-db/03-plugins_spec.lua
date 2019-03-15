local helpers = require "spec.helpers"


assert:set_parameter("TableFormatLevel", 10)


local UUID_PATTERN = "%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x"


for _, strategy in helpers.each_strategy() do
  describe("kong.db [#" .. strategy .. "]", function()
    local db, bp

    lazy_setup(function()
      bp, db = helpers.get_db_utils(strategy, {
        "routes",
        "services",
        "plugins",
      })
    end)

    describe("Plugins #plugins", function()

      local service

      before_each(function()
        service = bp.services:insert()
        assert(bp.routes:insert({ service = { id = service.id },
                                   protocols = { "tcp" },
                                   sources = { { ip = "127.0.0.1" } },
                                 }))
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
            run_on = "first",
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
          assert.same([[UNIQUE violation detected on '{service=null,]] ..
                      [[name="key-auth",route={id="]] .. route.id ..
                      [["},consumer=null}']], err_t.message)
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
            run_on = "first",
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
          assert.same([[UNIQUE violation detected on '{service=null,]] ..
                      [[name="key-auth",route={id="]] .. route.id ..
                      [["},consumer=null}']], err_t.message)
        end)
      end)
    end)

    describe(":load_plugin_schemas()", function()
      it("reports failure with missing plugins", function()
        local ok, err = db.plugins:load_plugin_schemas({
          ["missing"] = true,
        })
        assert.falsy(ok)
        assert.match("missing plugin is enabled but not installed", err, 1, true)
      end)

      it("reports failure with bad plugins #4392", function()
        local s = spy.on(kong.log, "warn")
        finally(function()
          mock.revert(kong.log)
        end)

        db.plugins:load_plugin_schemas({
          ["legacy-plugin-bad"] = true,
        })

        assert.spy(s).was_called(1)
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
