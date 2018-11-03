local enums = require "kong.enterprise_edition.dao.enums"
local helpers = require "spec.helpers"


for _, strategy in helpers.each_strategy() do

  describe("Admin API", function()
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
