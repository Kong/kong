local helpers = require "spec.helpers"
local cjson = require "cjson"

for _, strategy in helpers.each_strategy() do

  describe("Admin API #" .. strategy, function()
    local dao
    local db
    local client

    lazy_setup(function()
      _, db, dao = helpers.get_db_utils(strategy, {
        "apis",
        "plugins",
      }, {
        "key-auth"
      })

      assert(helpers.start_kong({
        database = strategy,
      }))
    end)

    lazy_teardown(function()
      helpers.stop_kong(nil, true)
    end)

    before_each(function()
      client = helpers.admin_client()
    end)

    after_each(function()
      if client then
        client:close()
      end
    end)

    describe("/plugins/enabled", function()
      it("returns a list of enabled plugins on this node", function()
        local res = assert(client:send {
          method = "GET",
          path = "/plugins/enabled",
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.is_table(json.enabled_plugins)
        assert.True(#json.enabled_plugins > 0)
      end)
    end)

    describe("/plugins", function()
      local plugins = {}

      lazy_setup(function()
        for i = 1, 3 do
          local api = assert(dao.apis:insert {
            name         = "api-" .. i,
            hosts        = { i .. "-api.com" },
            upstream_url = "http://example.com",
          })

          plugins[i] = assert(dao.plugins:insert {
            name = "key-auth",
            api = { id = api.id },
          })
        end
      end)

      describe("GET", function()
        it("retrieves all plugins configured", function()
          local res = assert(client:send {
            method = "GET",
            path = "/plugins"
          })
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)
          assert.equal(3, #json.data)
        end)
      end)
      it("returns 405 on invalid method", function()
        local methods = {"DELETE", "PATCH"}
        for i = 1, #methods do
          local res = assert(client:send {
            method = methods[i],
            path = "/plugins",
            body = {}, -- tmp: body to allow POST/PUT to work
            headers = {["Content-Type"] = "application/json"}
          })
          local body = assert.response(res).has.status(405)
          local json = cjson.decode(body)
          assert.same({ message = "Method not allowed" }, json)
        end
      end)

      describe("/plugins/{plugin}", function()
        describe("GET", function()
          it("retrieves a plugin by id", function()
            local res = assert(client:send {
              method = "GET",
              path = "/plugins/" .. plugins[1].id
            })
            local body = assert.res_status(200, res)
            local json = cjson.decode(body)
            assert.same(plugins[1], json)
          end)
          it("returns 404 if not found", function()
            local res = assert(client:send {
              method = "GET",
              path = "/plugins/f4aecadc-05c7-11e6-8d41-1f3b3d5fa15c"
            })
            assert.res_status(404, res)
          end)
        end)


        describe("PATCH", function()
          it("updates a plugin", function()
            local res = assert(client:send {
              method = "PATCH",
              path = "/plugins/" .. plugins[1].id,
              body = {enabled = false},
              headers = {["Content-Type"] = "application/json"}
            })
            local body = assert.res_status(200, res)
            local json = cjson.decode(body)
            assert.False(json.enabled)

            local in_db = assert(db.plugins:select({ id = plugins[1].id }, { nulls = true }))
            assert.same(json, in_db)
          end)
          it("updates a plugin bis", function()
            local plugin = assert(db.plugins:select({ id = plugins[2].id }))

            plugin.enabled = not plugin.enabled
            plugin.created_at = nil

            local res = assert(client:send {
              method = "PATCH",
              path = "/plugins/" .. plugin.id,
              body = plugin,
              headers = {["Content-Type"] = "application/json"}
            })
            local body = assert.res_status(200, res)
            local json = cjson.decode(body)
            assert.equal(plugin.enabled, json.enabled)
          end)
          describe("errors", function()
            it("returns 404 if not found", function()
              local res = assert(client:send {
                method = "PATCH",
                path = "/plugins/f4aecadc-05c7-11e6-8d41-1f3b3d5fa15c",
                body = {enabled = false},
                headers = {["Content-Type"] = "application/json"}
              })
              assert.res_status(404, res)
            end)
          end)
        end)

        describe("DELETE", function()
          it("deletes by id", function()
            local res = assert(client:send {
              method = "DELETE",
              path = "/plugins/" .. plugins[3].id
            })
            assert.res_status(204, res)
          end)
          describe("errors", function()
            it("returns 204 if not found", function()
              local res = assert(client:send {
                method = "DELETE",
                path = "/plugins/f4aecadc-05c7-11e6-8d41-1f3b3d5fa15c"
              })
              assert.res_status(204, res)
            end)
          end)
        end)
      end)
    end)

    describe("/plugins/schema/{plugin}", function()
      describe("GET", function()
        it("returns the schema of a plugin config", function()
          local res = assert(client:send {
            method = "GET",
            path = "/plugins/schema/key-auth",
          })
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)
          assert.is_table(json.fields)
        end)
        it("returns 404 on invalid plugin", function()
          local res = assert(client:send {
            method = "GET",
            path = "/plugins/schema/foobar",
          })
          local body = assert.res_status(404, res)
          local json = cjson.decode(body)
          assert.same({ message = "No plugin named 'foobar'" }, json)
        end)
      end)
    end)
  end)
end
