local helpers = require "spec.helpers"
local cjson = require "cjson"
local uuid = require("kong.tools.uuid").uuid


describe("an old plugin: translate_backwards", function()
  local bp, db, route, admin_client
  local plugin_id = uuid()

  lazy_setup(function()
    helpers.test_conf.lua_package_path = helpers.test_conf.lua_package_path .. ";./spec-ee/fixtures/custom_plugins/?.lua"
    bp, db = helpers.get_db_utils(nil, {
      "plugins",
    }, { 'translate-backwards-older-plugin' })

    route = assert(bp.routes:insert {
      hosts = { "redis.test" },
    })

    assert(helpers.start_kong({
      plugins = "bundled,translate-backwards-older-plugin",
      nginx_conf = "spec/fixtures/custom_nginx.template",
      lua_package_path  = "?./spec-ee/fixtures/custom_plugins/?.lua",
    }))

    admin_client = assert(helpers.admin_client())
  end)

  lazy_teardown(function()
    if admin_client then
      admin_client:close()
    end

    helpers.stop_kong()
  end)

  describe("when creating custom plugin", function()
    after_each(function()
      db:truncate("plugins")
    end)

    describe("when using the new field", function()
      it("creates the custom plugin and fills in old field in response", function()
        -- POST
        local res = assert(admin_client:send {
          method = "POST",
          route = {
            id = route.id
          },
          path = "/plugins",
          headers = { ["Content-Type"] = "application/json" },
          body = {
            id = plugin_id,
            name = "translate-backwards-older-plugin",
            config = {
              new_field = "ABC"
            },
          },
        })

        local json = cjson.decode(assert.res_status(201, res))
        assert.same(json.config.new_field, "ABC")
        assert.same(json.config.old_field, "ABC")

        -- PATCH
        res = assert(admin_client:send {
          method = "PATCH",
          path = "/plugins/" .. plugin_id,
          headers = { ["Content-Type"] = "application/json" },
          body = {
            name = "translate-backwards-older-plugin",
            config = {
              new_field = "XYZ"
            },
          },
        })

        json = cjson.decode(assert.res_status(200, res))
        assert.same(json.config.new_field, "XYZ")
        assert.same(json.config.old_field, "XYZ")

        -- GET
        res = assert(admin_client:send {
          method = "GET",
          path = "/plugins/" .. plugin_id
        })

        json = cjson.decode(assert.res_status(200, res))
        assert.same(json.config.new_field, "XYZ")
        assert.same(json.config.old_field, "XYZ")
      end)
    end)

    describe("when using the old field", function()
      it("creates the custom plugin and fills in old field in response", function()
        -- POST
        local res = assert(admin_client:send {
          method = "POST",
          route = {
            id = route.id
          },
          path = "/plugins",
          headers = { ["Content-Type"] = "application/json" },
          body = {
            id = plugin_id,
            name = "translate-backwards-older-plugin",
            config = {
              old_field = "ABC"
            },
          },
        })

        local json = cjson.decode(assert.res_status(201, res))
        assert.same(json.config.new_field, "ABC")
        assert.same(json.config.old_field, "ABC")

        -- PATCH
        res = assert(admin_client:send {
          method = "PATCH",
          path = "/plugins/" .. plugin_id,
          headers = { ["Content-Type"] = "application/json" },
          body = {
            name = "translate-backwards-older-plugin",
            config = {
              old_field = "XYZ"
            },
          },
        })

        json = cjson.decode(assert.res_status(200, res))
        assert.same(json.config.new_field, "XYZ")
        assert.same(json.config.old_field, "XYZ")

        -- GET
        res = assert(admin_client:send {
          method = "GET",
          path = "/plugins/" .. plugin_id
        })

        json = cjson.decode(assert.res_status(200, res))
        assert.same(json.config.new_field, "XYZ")
        assert.same(json.config.old_field, "XYZ")
      end)
    end)

    describe("when using the both new and old fields", function()
      describe("when their values match", function()
        it("creates the custom plugin and fills in old field in response", function()
          -- POST
          local res = assert(admin_client:send {
            method = "POST",
            route = {
              id = route.id
            },
            path = "/plugins",
            headers = { ["Content-Type"] = "application/json" },
            body = {
              id = plugin_id,
              name = "translate-backwards-older-plugin",
              config = {
                new_field = "ABC",
                old_field = "ABC"
              },
            },
          })

          local json = cjson.decode(assert.res_status(201, res))
          assert.same(json.config.new_field, "ABC")
          assert.same(json.config.old_field, "ABC")

          -- PATCH
          res = assert(admin_client:send {
            method = "PATCH",
            path = "/plugins/" .. plugin_id,
            headers = { ["Content-Type"] = "application/json" },
            body = {
              name = "translate-backwards-older-plugin",
              config = {
                new_field = "XYZ",
                old_field = "XYZ"
              },
            },
          })

          json = cjson.decode(assert.res_status(200, res))
          assert.same(json.config.new_field, "XYZ")
          assert.same(json.config.old_field, "XYZ")

          -- GET
          res = assert(admin_client:send {
            method = "GET",
            path = "/plugins/" .. plugin_id
          })

          json = cjson.decode(assert.res_status(200, res))
          assert.same(json.config.new_field, "XYZ")
          assert.same(json.config.old_field, "XYZ")
        end)
      end)

      describe("when their values mismatch", function()
        it("rejects such plugin", function()
          -- POST --- with mismatched values
          local res = assert(admin_client:send {
            method = "POST",
            route = {
              id = route.id
            },
            path = "/plugins",
            headers = { ["Content-Type"] = "application/json" },
            body = {
              id = plugin_id,
              name = "translate-backwards-older-plugin",
              config = {
                new_field = "ABC",
                old_field = "XYZ"
              },
            },
          })

          assert.res_status(400, res)

          -- POST --- with correct values so that we can send PATCH below
          res = assert(admin_client:send {
            method = "POST",
            route = {
              id = route.id
            },
            path = "/plugins",
            headers = { ["Content-Type"] = "application/json" },
            body = {
              id = plugin_id,
              name = "translate-backwards-older-plugin",
              config = {
                new_field = "ABC",
                old_field = "ABC"
              },
            },
          })

          local json = cjson.decode(assert.res_status(201, res))
          assert.same(json.config.new_field, "ABC")
          assert.same(json.config.old_field, "ABC")

          -- PATCH
          res = assert(admin_client:send {
            method = "PATCH",
            path = "/plugins/" .. plugin_id,
            headers = { ["Content-Type"] = "application/json" },
            body = {
              name = "translate-backwards-older-plugin",
              config = {
                new_field = "EFG",
                old_field = "XYZ"
              },
            },
          })

          assert.res_status(400, res)

          -- GET
          res = assert(admin_client:send {
            method = "GET",
            path = "/plugins/" .. plugin_id
          })

          json = cjson.decode(assert.res_status(200, res))
          assert.same(json.config.new_field, "ABC")
          assert.same(json.config.old_field, "ABC")
        end)
      end)
    end)
  end)
end)
