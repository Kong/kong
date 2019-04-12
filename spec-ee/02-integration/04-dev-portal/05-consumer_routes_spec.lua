local cjson = require "cjson.safe"
local helpers = require "spec.helpers"
local enums = require "kong.enterprise_edition.dao.enums"
local utils = require "kong.tools.utils"

for _, strategy in helpers.each_strategy() do
  describe("Admin API - Consumers #" .. strategy, function()
    local bp
    local client
    local admin, proxy, developer

    setup(function()
      bp, _, _ = helpers.get_db_utils(strategy)
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

          developer = assert(bp.consumers:insert {
            username = "developerbob",
            custom_id = "1337",
            type = enums.CONSUMERS.TYPE.DEVELOPER
          })
        end)
        it("returns only consumers of type PROXY", function()
          local res = assert(client:send {
            method = "GET",
            path = "/consumers",
          })

          local body = assert.res_status(200, res)
          local json = cjson.decode(body)

          assert.equal(proxy.id, json.data[1].id)
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
        end)

        it("returns 404 if type developer", function()
          local res = assert(client:send {
            method = "GET",
            path = "/consumers/" .. developer.username
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
  end)

end
