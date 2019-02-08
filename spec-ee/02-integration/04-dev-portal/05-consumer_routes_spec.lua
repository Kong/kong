local cjson = require "cjson.safe"
local helpers = require "spec.helpers"
local enums = require "kong.enterprise_edition.dao.enums"

for _, strategy in helpers.each_strategy() do

  describe("#flaky Admin API", function()
    local bp, dao
    local client
    local admin, developer

    setup(function()
      bp, _, dao = helpers.get_db_utils(strategy)
      assert(helpers.start_kong({
        database = strategy
      }))
      helpers.register_consumer_relations(dao)

      admin = assert(bp.consumers:insert {
        username = "adminbob",
        custom_id = "12347",
        type = enums.CONSUMERS.TYPE.ADMIN
      })
      developer = assert(bp.consumers:insert {
        username = "developerbob",
        custom_id = "1337",
        type = enums.CONSUMERS.TYPE.DEVELOPER
      })

      client = helpers.admin_client()
    end)

    teardown(function()
      if client then client:close() end
      helpers.stop_kong()
    end)

    describe("/consumers", function()
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
          assert.equal("type is invalid", cjson.decode(body).message)
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
          assert.equal("type is invalid", cjson.decode(body).message)
        end)
      end)

      describe("PUT", function()
        it("returns 409 when trying to change consumer type to proxy", function()
          local res = assert(client:send {
            method = "PUT",
            path = "/consumers",
            body = {
              username = "adminbob",
              type = enums.CONSUMERS.TYPE.PROXY
            },
            headers = {
              ["Content-Type"] = "application/json"
            }
          })

          local body = assert.res_status(409, res)
          assert.equal("already exists with value 'adminbob'",
                       cjson.decode(body).username)
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
      end)
      describe("GET", function()
        it("returns 404 if type developer", function()
          local res = assert(client:send {
            method = "GET",
            path = "/consumers/" .. developer.username
          })
          assert.res_status(404, res)
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
