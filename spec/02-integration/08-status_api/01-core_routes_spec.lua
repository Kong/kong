local helpers = require "spec.helpers"
local cjson = require "cjson"

local strategies = {}
for _, strategy in helpers.each_strategy() do
  table.insert(strategies, strategy)
end
table.insert(strategies, "off")
for _, strategy in pairs(strategies) do
describe("Status API - with strategy #" .. strategy, function()
  local client

  lazy_setup(function()
    helpers.get_db_utils(nil, {}) -- runs migrations
    assert(helpers.start_kong {
      status_listen = "127.0.0.1:9500",
      plugins = "admin-api-method",
    })
    client = helpers.http_client("127.0.0.1", 9500, 20000)
  end)

  lazy_teardown(function()
    if client then client:close() end
    helpers.stop_kong()
  end)

  describe("core", function()
    it("/status returns status info", function()
      local res = assert(client:send {
        method = "GET",
        path = "/status"
      })
      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      assert.is_table(json.database)
      assert.is_table(json.server)

      assert.is_boolean(json.database.reachable)

      assert.is_number(json.server.connections_accepted)
      assert.is_number(json.server.connections_active)
      assert.is_number(json.server.connections_handled)
      assert.is_number(json.server.connections_reading)
      assert.is_number(json.server.connections_writing)
      assert.is_number(json.server.connections_waiting)
      assert.is_number(json.server.total_requests)
    end)
  end)

  describe("plugins", function()
    it("can add endpoints", function()
      local res = assert(client:send {
        method = "GET",
        path = "/hello"
      })
      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      assert.same(json, { hello = "from status api" })
    end)
  end)
end)
end
