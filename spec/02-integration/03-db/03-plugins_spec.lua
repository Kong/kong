local helpers = require "spec.helpers"


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

    before_each(function()
      service = bp.services:insert()
      route = bp.routes:insert({ protocols = { "tcp" },
                                 sources = { { ip = "127.0.0.1" } },
                               })
    end)

    describe("Plugins #plugins", function()
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
            protocols = { "http", "https" },
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

        it("returns an error when inserting mismatched plugins", function()
          local plugin, _, err_t = db.plugins:insert({ name = "key-auth",
                                                       protocols = { "http" },
                                                       route = { id = route.id },
                                                     })
          assert.is_nil(plugin)
          assert.equals(err_t.fields.protocols, "must match the associated route's protocols")

          local plugin, _, err_t = db.plugins:insert({ name = "key-auth",
                                                       protocols = { "tcp" },
                                                       service = { id = service.id },
                                                     })
          assert.is_nil(plugin)
          assert.equals(err_t.fields.protocols,
                        "must match the protocols of at least one route pointing to this Plugin's service")
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
            protocols = { "http", "https" },
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
                                              { route = { id = route.id } })
        assert.is_nil(p)
        assert.equals(err_t.fields.protocols, "must match the associated route's protocols")


        local p, _, err_t = db.plugins:upsert({ id = global_plugin.id },
                                              { service = { id = service.id } })
        assert.is_nil(p)
        assert.equals(err_t.fields.protocols,
                      "must match the protocols of at least one route pointing to this Plugin's service")
      end)
    end)
  end) -- kong.db [strategy]
end
