local helpers = require "spec.helpers"


local UUID_PATTERN = "%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x"


for _, strategy in helpers.each_strategy() do
  describe("kong.db [#" .. strategy .. "]", function()
    local db, bp

    setup(function()
      bp, db = helpers.get_db_utils(strategy)
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
          assert.same([[UNIQUE violation detected on '{consumer=null,]] ..
                      [[api=null,service=null,name="key-auth",route={id="]] ..
                      route.id .. [["}}']], err_t.message)
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
          assert.same([[UNIQUE violation detected on '{consumer=null,]] ..
                      [[api=null,service=null,name="key-auth",route={id="]] ..
                      route.id .. [["}}']], err_t.message)
        end)
      end)
    end)

  end) -- kong.db [strategy]
end
