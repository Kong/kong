local helpers = require "spec.helpers"
local cjson = require "cjson"

for _, strategy in helpers.all_strategies() do
  describe("Status API - with strategy #" .. strategy, function()
    lazy_setup(function()
      helpers.get_db_utils(nil, {}) -- runs migrations
    end)

    it("default enable", function()
      assert.truthy(helpers.kong_exec("start -c spec/fixtures/default_status_listen.conf"))
      local client = helpers.http_client("127.0.0.1", 8007, 20000)
      finally(function()
        helpers.stop_kong()
        client:close()
      end)

      local res = assert(client:send {
        method = "GET",
        path = "/status",
      })

      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      assert.is_table(json.server)

      assert.is_number(json.server.connections_accepted)
      assert.is_number(json.server.connections_active)
      assert.is_number(json.server.connections_handled)
      assert.is_number(json.server.connections_reading)
      assert.is_number(json.server.connections_writing)
      assert.is_number(json.server.connections_waiting)
      assert.is_number(json.server.total_requests)
    end)
  end)
end
