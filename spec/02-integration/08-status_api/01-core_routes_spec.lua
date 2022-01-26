local helpers = require "spec.helpers"
local cjson = require "cjson"


for _, strategy in helpers.all_strategies() do
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
    it("/status returns status info without configuration_hash", function()
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
      assert.is_nil(json.server.configuration_hash) -- no hash in DB mode, or in DBLESS mode until configuration has been applied
    end)

    it("/status starts providing a configuration_hash once an initial configuration has been pushed in dbless mode #off", function()
      -- push an initial configuration so that a configuration_hash will be present
      local postres = assert(client:send {
        method = "POST",
        path = "/config",
        body = {
          config = [[
          _format_version: "1.1"
          services:
          - host = "konghq.com"
          ]],
        },
        headers = {
          ["Content-Type"] = "application/json"
        }
      })
      assert.res_status(201, postres)

      -- verify the status endpoint now includes a value (other than the default) for the configuration_hash
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
      assert.is_string(json.server.configuration_hash)
      assert.equal(32, #json.server.configuration_hash)
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
