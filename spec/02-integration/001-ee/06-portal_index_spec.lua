local helpers      = require "spec.helpers"
local ee_helpers   = require "spec.ee_helpers"

-- TODO: Cassandra
for _, strategy in helpers.each_strategy('postgres') do
  describe("portal index", function()
    local dao
    local client

    setup(function()
      _, _, dao = helpers.get_db_utils(strategy)
    end)

    teardown(function()
      helpers.stop_kong()
    end)

    describe("router", function ()
      local portal_gui_client

      before_each(function()
        helpers.stop_kong()
        helpers.register_consumer_relations(dao)

        assert(helpers.start_kong({
          database    = strategy,
          portal      = true,
          portal_auth = "basic-auth"
        }))

        client = assert(helpers.admin_client())
        portal_gui_client = assert(ee_helpers.portal_gui_client())
      end)

      after_each(function()
        if client then
          client:close()
        end

        if portal_gui_client then
          portal_gui_client:close()
        end
      end)

      it("correctly identifies default workspace", function()        

        local res = assert(portal_gui_client:send {
          method = "GET",
          path = "/",
        })
        local body = assert.res_status(200, res)
        assert.not_nil(string.match(body, '<meta name="KONG:WORKSPACE" content="default" />'))

        res = assert(portal_gui_client:send {
          method = "GET",
          path = "/hello",
        })
        body = assert.res_status(200, res)
        assert.not_nil(string.match(body, '<meta name="KONG:WORKSPACE" content="default" />'))

        res = assert(portal_gui_client:send {
          method = "GET",
          path = "/hello/goodbye",
        })
        body = assert.res_status(200, res)
        assert.not_nil(string.match(body, '<meta name="KONG:WORKSPACE" content="default" />'))
      end)

      it("correctly identifies custom workspace", function()  
        assert(client:send {
          method = "POST",
          path = "/workspaces",
          body = {
            name = "team_gruce",
          },
          headers = {["Content-Type"] = "application/json"},
        })

        local res = assert(portal_gui_client:send {
          method = "GET",
          path = "/"
        })
        local body = assert.res_status(200, res)
        assert.not_nil(string.match(body, '<meta name="KONG:WORKSPACE" content="default" />'))

        res = assert(portal_gui_client:send {
          method = "GET",
          path = "/team_gruce"
        })
        body = assert.res_status(200, res)
        assert.not_nil(string.match(body, '<meta name="KONG:WORKSPACE" content="team_gruce" />'))

        res = assert(portal_gui_client:send {
          method = "GET",
          path = "/team_gruce/endpoint"
        })
        body = assert.res_status(200, res)
        assert.not_nil(string.match(body, '<meta name="KONG:WORKSPACE" content="team_gruce" />'))

        res = assert(portal_gui_client:send {
          method = "GET",
          path = "/team_gruce/endpoint/another_endpoint"
        })
        body = assert.res_status(200, res)
        assert.not_nil(string.match(body, '<meta name="KONG:WORKSPACE" content="team_gruce" />'))

        res = assert(portal_gui_client:send {
          method = "GET",
          path = "/team_gruce/default"
        })
        body = assert.res_status(200, res)
        assert.not_nil(string.match(body, '<meta name="KONG:WORKSPACE" content="team_gruce" />'))
      end)

      it("correctly overrides default (conf.default) config when workspace config present", function()  
        assert(client:send {
          method = "POST",
          path = "/workspaces",
          body = {
            name = "team_gruce",
            config = {
              portal_auth = "key-auth"
            },
          },
          headers = {["Content-Type"] = "application/json"},
        })

        local res = assert(portal_gui_client:send {
          method = "GET",
          path = "/default"
        })
        local body = assert.res_status(200, res)
        assert.not_nil(string.match(body, '<meta name="KONG:PORTAL_AUTH" content="basic%-auth" />'))

        res = assert(portal_gui_client:send {
          method = "GET",
          path = "/team_gruce"
        })
        body = assert.res_status(200, res)
        assert.not_nil(string.match(body, '<meta name="KONG:PORTAL_AUTH" content="key%-auth" />'))
      end)
    end)
  end)
end
