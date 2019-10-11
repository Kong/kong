local cjson = require "cjson.safe"
local helpers = require "spec.helpers"
local enums = require "kong.enterprise_edition.dao.enums"
local utils = require "kong.tools.utils"


for _, strategy in helpers.each_strategy() do
  describe("Admin API - Consumers #" .. strategy, function()
    local bp, db
    local client
    local admin, proxy, developer
    local admin_ws, proxy_ws, developer_ws
    local foo_ws

    setup(function()
      bp, db, _ = helpers.get_db_utils(strategy)
      assert(helpers.start_kong({
        database = strategy
      }))

      client = helpers.admin_client()
    end)

    teardown(function()
      if client then client:close() end
      helpers.stop_kong()
    end)

    describe("/consumers", function()
      describe("GET - empty", function()
        it("returns an array on empty dataset", function()
          local res = assert(client:send {
            method = "GET",
            path = "/consumers",
          })

          local body = assert.res_status(200, res)
          local json = cjson.decode(body)

          assert(utils.is_array(json.data))
          assert.equal(0, #json.data)
          assert.equal('{"next":null,"data":[]}', body)
        end)
      end)

      describe("GET", function()
        setup(function()
          admin = assert(bp.consumers:insert {
            username = "adminbob",
            custom_id = "12347",
            type = enums.CONSUMERS.TYPE.ADMIN
          })

          proxy = assert(bp.consumers:insert {
            username = "proxybob",
          })

          assert(bp.consumers:insert {
            username = "proxybob2",
          })

          assert(bp.consumers:insert {
            username = "proxybob3",
          })

          developer = assert(bp.consumers:insert {
            username = "developerbob",
            custom_id = "1337",
            type = enums.CONSUMERS.TYPE.DEVELOPER
          })

          -- foo workspace
          foo_ws = bp.workspaces:insert({ name = "foo" })
          admin_ws = assert(bp.consumers:insert_ws( {
            username = "adminbob",
            custom_id = "12347",
            type = enums.CONSUMERS.TYPE.ADMIN
          }, foo_ws))

          proxy_ws = assert(bp.consumers:insert_ws( {
            username = "proxybob",
          }, foo_ws))

          developer_ws = assert(bp.consumers:insert_ws( {
            username = "developerbob",
            custom_id = "1337",
            type = enums.CONSUMERS.TYPE.DEVELOPER
          }, foo_ws))
        end)

        it("paginates only through PROXY consumers", function()
          local res = assert(client:send {
            method = "GET",
            path = "/consumers?size=2",
          })
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)

          assert.equals(2, #json.data)
          assert.not_nil(json.next)
        end)

        it("returns only consumers of type PROXY", function()
          local res = assert(client:send {
            method = "GET",
            path = "/consumers",
          })

          local body = assert.res_status(200, res)
          local json = cjson.decode(body)

          assert.equal(3, #json.data)
          local ids = require("pl.tablex").map(function(x) return x.id end, json.data)
          assert.contains(proxy.id, ids)

          local res = assert(client:send {
            method = "GET",
            path = "/foo/consumers",
          })

          local body = assert.res_status(200, res)
          local json = cjson.decode(body)

          assert.equal(proxy_ws.id, json.data[1].id)
          assert.equal(1, #json.data)
        end)
      end)

      describe("POST", function()
        it("returns 400 when trying to create consumer of type=admin", function()
          local res = assert(client:send {
            method = "POST",
            path = "/consumers",
            body = {
              username = "the_dood",
              type = enums.CONSUMERS.TYPE.ADMIN
            },
            headers = {
              ["Content-Type"] = "application/json"
            }
          })
          local body = assert.res_status(400, res)
          assert.equal("Invalid parameter: 'type'", cjson.decode(body).message)

          local res = assert(client:send {
            method = "POST",
            path = "/foo/consumers",
            body = {
              username = "the_dood",
              type = enums.CONSUMERS.TYPE.ADMIN
            },
            headers = {
              ["Content-Type"] = "application/json"
            }
          })
          local body = assert.res_status(400, res)
          assert.equal("Invalid parameter: 'type'", cjson.decode(body).message)
        end)

        it("returns 400 when trying to create consumer of type=developer", function()
          local res = assert(client:send {
            method = "POST",
            path = "/consumers",
            body = {
              username = "the_doodette",
              type = enums.CONSUMERS.TYPE.DEVELOPER
            },
            headers = {
              ["Content-Type"] = "application/json"
            }
          })

          local body = assert.res_status(400, res)
          assert.equal("Invalid parameter: 'type'", cjson.decode(body).message)

          local res = assert(client:send {
            method = "POST",
            path = "/foo/consumers",
            body = {
              username = "the_doodette",
              type = enums.CONSUMERS.TYPE.DEVELOPER
            },
            headers = {
              ["Content-Type"] = "application/json"
            }
          })

          local body = assert.res_status(400, res)
          assert.equal("Invalid parameter: 'type'", cjson.decode(body).message)
        end)
      end)
    end)

    describe("/consumers/:username_or_id", function()
      describe("GET", function()
        it("returns 404 if type admin", function()
          local res = assert(client:send {
            method = "GET",
            path = "/consumers/" .. admin.username
          })
          assert.res_status(404, res)

          local res = assert(client:send {
            method = "GET",
            path = "/foo/consumers/" .. admin_ws.username
          })
          assert.res_status(404, res)
        end)

        it("returns 404 if type developer", function()
          local res = assert(client:send {
            method = "GET",
            path = "/consumers/" .. developer.username
          })
          assert.res_status(404, res)

          local res = assert(client:send {
            method = "GET",
            path = "/foo/consumers/" .. developer_ws.username
          })
          assert.res_status(404, res)
        end)
      end)

      describe("PUT", function()
        it("returns 400 when trying to change consumer type to proxy", function()
          local res = assert(client:send {
            method = "PUT",
            path = "/consumers/adminbob",
            body = {
              type = enums.CONSUMERS.TYPE.PROXY,
            },
            headers = {
              ["Content-Type"] = "application/json"
            }
          })

          assert.res_status(400, res)

          local res = assert(client:send {
            method = "PUT",
            path = "/foo/consumers/adminbob",
            body = {
              type = enums.CONSUMERS.TYPE.PROXY,
            },
            headers = {
              ["Content-Type"] = "application/json"
            }
          })

          assert.res_status(400, res)
        end)

        it("returns 400 when trying to create consumer type of admin", function()
          local res = assert(client:send {
            method = "PUT",
            path = "/consumers/unknown-admin",
            body = {
              type = enums.CONSUMERS.TYPE.ADMIN,
            },
            headers = {
              ["Content-Type"] = "application/json"
            }
          })

          assert.res_status(400, res)

          local res = assert(client:send {
            method = "PUT",
            path = "/foo/consumers/unknown-admin",
            body = {
              type = enums.CONSUMERS.TYPE.ADMIN,
            },
            headers = {
              ["Content-Type"] = "application/json"
            }
          })

          assert.res_status(400, res)
        end)
      end)
    end)

    describe("/consumers/:username_or_id/plugins", function()
      describe("GET", function()
        it("returns 404 if type admin", function()
          local res = assert(client:send {
            method = "GET",
            path = "/consumers/" .. admin.username .. "/plugins"
          })
          assert.res_status(404, res)

          local res = assert(client:send {
            method = "GET",
            path = "/foo/consumers/" .. admin_ws.username .. "/plugins"
          })
          assert.res_status(404, res)
        end)
      end)
      describe("GET", function()
        it("returns 404 if type developer", function()
          local res = assert(client:send {
            method = "GET",
            path = "/consumers/" .. developer.username .. "/plugins"
          })
          assert.res_status(404, res)
        end)
      end)
    end)

    describe("consumer:page_by_type", function()
      setup(function()
        db:truncate("consumers")

        for i = 1, 101 do
          bp.consumers:insert({ username = "user-" .. i })
        end
        for i = 1, 101 do
          bp.consumers:insert_ws({ username = "user-" .. i }, foo_ws)
        end
      end)
      it("default page size", function()
        local res = assert(client:send {
          method = "GET",
          path = "/consumers",
        })

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)

        assert.equal(100, #json.data)
        assert.not_nil(json.offset)
        assert.not_nil(json.next)

        local res = assert(client:send {
          method = "GET",
          path = "/foo/consumers",
        })

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)

        assert.equal(100, #json.data)
        assert.not_nil(json.offset)
        assert.not_nil(json.next)
      end)

      it("exact page size", function()
        local page_size = 101
        if strategy == "cassandra" then
          --  cassandra only detects the end of a pagination when
          -- we go past the number of rows in the iteration - it doesn't
          -- seem to detect the pages ending at the limit
          page_size = page_size + 1
        end
        local res = assert(client:send {
          method = "GET",
          path = "/consumers?size=" .. page_size,
        })

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)

        assert.equal(101, #json.data)
        assert.is_nil(json.offset)
      end)
      it("page offset", function()
        local page_size = 100

        local res = assert(client:send {
          method = "GET",
          path = "/consumers?size=" .. page_size,
        })

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)

        assert.equal(100, #json.data)
        assert.not_nil(json.offset)
        assert.not_nil(json.next)

        local res = assert(client:send {
          method = "GET",
          path = json.next,
        })

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)

        assert.equal(1, #json.data)
      end)
      it("returns created_at as epoch time", function()
        local res = assert(client:send {
          method = "GET",
          path = "/consumers?size=1",
        })

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)

        assert.same("number", type(json.data[1].created_at))
      end)
    end)
  end)

end
