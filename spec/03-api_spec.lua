local cjson   = require "cjson"
local helpers = require "spec.helpers"


for _, strategy in helpers.each_strategy() do
  describe("Plugin: collector (API) [#" .. strategy .. "]", function()
    local admin_client
    local bp
    local db
    local workspace1
    local workspace2

    setup(function()
      local plugin_config = {
        host = 'collector',
        port = 5000,
        https = false,
        log_bodies = true,
        queue_size = 1,
        flush_timeout = 1
      }
      bp, db = helpers.get_db_utils(strategy, nil, { "collector" })

      workspace1 = bp.workspaces:insert({ name = "workspace1"})
      workspace2 = bp.workspaces:insert({ name = "workspace2"})

      bp.plugins:insert_ws({ name = "collector", config = plugin_config }, workspace1)
      bp.plugins:insert_ws({ name = "collector", config = plugin_config }, workspace2)

      assert(helpers.start_kong({ database = strategy, plugins = "collector" }))
      admin_client = helpers.admin_client()
    end)

    before_each(function()
      db:truncate("service_maps")
    end)

    teardown(function()
      if admin_client then
        admin_client:close()
      end

      helpers.stop_kong()
    end)

    describe("/service_maps", function()
      describe("POST", function()
        it("it stores the given service map data", function()
          local res = assert(admin_client:send {
            method = "POST",
            path = "/workspace1/service_maps",
            body = { service_map = cjson.encode({ id = workspace1.name})},
            headers = { ["Content-Type"] = "application/json" }
          })
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)
          assert.equal(workspace1.name, json.id)

          -- the above POST should not affect workspace2
          local res = assert(admin_client:send {
            method = "GET",
            path = "/workspace2/service_maps",
          })
          assert.res_status(404, res)
        end)
      end)

      describe("GET", function()
        before_each(function()
          local res = assert(admin_client:send {
            method = "POST",
            path = "/workspace2/service_maps",
            body = { service_map = cjson.encode({ id = "workspace2"})},
            headers = { ["Content-Type"] = "application/json" }
          })
          assert.res_status(200, res)
        end)
        it("returns the workspace service-map", function()
          local res = assert(admin_client:send {
            method  = "GET",
            path    = "/workspace2/service_maps"
          })
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)
          assert.equal(workspace2.name, json.data[1].id)
        end)
        it("returns the 404 for workspace without service-map", function()
          local res = assert(admin_client:send {
            method  = "GET",
            path    = "/workspace1/service_maps"
          })
          assert.res_status(404, res)
        end)
      end)
    end)
  end)
end
