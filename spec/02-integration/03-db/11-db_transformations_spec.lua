local helpers = require "spec.helpers"


local fmt = string.format


for _, strategy in helpers.each_strategy() do
  describe("kong.db [#" .. strategy .. "]", function()
    local _, db

    lazy_setup(function()
      _, db = helpers.get_db_utils(strategy, {
        "transformations",
      }, {
        "transformations"
      })

      local env = {}
      env.database = strategy
      env.plugins = env.plugins or "transformations"

      local lua_path = [[ KONG_LUA_PATH_OVERRIDE="./spec/fixtures/migrations/?.lua;]] ..
                       [[./spec/fixtures/migrations/?/init.lua;]]                     ..
                       [[./spec/fixtures/custom_plugins/?.lua;]]                      ..
                       [[./spec/fixtures/custom_plugins/?/init.lua;" ]]

      local cmdline = "migrations up -c " .. helpers.test_conf_path
      local _, code, _, stderr = helpers.kong_exec(cmdline, env, true, lua_path)
      assert.same(0, code)
      assert.equal("", stderr)
    end)

    describe("Transformations", function()
      describe(":update()", function()
        local errmsg = fmt("[%s] schema violation (all or none of these fields must be set: 'hash_secret', 'secret')",
                           strategy)

        it("updating secret requires hash_secret", function()
          local dao = assert(db.transformations:insert({
            name = "test"
          }))

          local newdao, err = db.transformations:update({ id = dao.id }, {
            secret = "dog",
          })

          assert.equal(nil, newdao)
          assert.equal(errmsg, err)

          assert(db.transformations:delete({ id = dao.id }))
        end)

        it("updating hash_secret requires secret", function()
          local dao = assert(db.transformations:insert({
            name = "test"
          }))

          local newdao, err = db.transformations:update({ id = dao.id }, {
            hash_secret = true,
          })

          assert.equal(nil, newdao)
          assert.equal(errmsg, err)

          assert(db.transformations:delete({ id = dao.id }))
        end)
      end)

      it("vault references are resolved after transformations", function()
        finally(function()
          helpers.unsetenv("META_VALUE")
        end)
        helpers.setenv("META_VALUE", "123456789")

        require "kong.vaults.env".init()

        local dao = assert(db.transformations:insert({
          name = "test"
        }))

        local newdao = assert(db.transformations:update({ id = dao.id }, {
          meta = "{vault://env/meta-value}",
        }))

        assert.equal("123456789", newdao.meta)
        assert.same({
          meta = "{vault://env/meta-value}",
        }, newdao["$refs"])
        assert(db.transformations:delete({ id = dao.id }))
      end)
    end)

  end) -- kong.db [strategy]
end
