local helpers = require "spec.helpers"
local cjson = require "cjson"


for _, strategy in helpers.all_strategies() do
describe("Status API #" .. strategy, function()

  lazy_setup(function()
    helpers.get_db_utils(strategy, {
      "plugins",
      "routes",
      "services",
    })
    assert(helpers.start_kong {
      status_listen = "127.0.0.1:9500",
      plugins = "admin-api-method",
      database = strategy,
    })
  end)

  lazy_teardown(function()
    helpers.stop_kong()
  end)

  describe("core", function()
    it("/status returns status info with blank configuration_hash (declarative config) or without it (db mode)", function()
      local client = helpers.http_client("127.0.0.1", 9500, 20000)
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
      if strategy == "off" then
        assert.is_equal(string.rep("0", 32), json.configuration_hash) -- all 0 in DBLESS mode until configuration is applied
      else
        assert.is_nil(json.configuration_hash) -- not present in DB mode
      end
      client:close()
    end)
  end)


  describe("plugins", function()
    it("can add endpoints", function()
      local client = helpers.http_client("127.0.0.1", 9500, 20000)
      local res = assert(client:send({
        method = "GET",
        path = "/hello"
      }))
      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      assert.same(json, { hello = "from status api" })
      client:close()
    end)
  end)
end)

describe("Status API #" .. strategy, function()
  local h2_client

  lazy_setup(function()
    helpers.get_db_utils(strategy, {})
    assert(helpers.start_kong({
      status_listen = "127.0.0.1:9500 ssl http2",
    }))
    h2_client = helpers.http2_client("127.0.0.1", 9500, true)
  end)

  lazy_teardown(function()
    helpers.stop_kong()
  end)

  it("supports HTTP/2", function()
    local res, headers = assert(h2_client({
      headers = {
        [":method"] = "GET",
        [":path"] = "/status",
        [":authority"] = "127.0.0.1:9500",
      },
    }))
    local json = cjson.decode(res)

    assert.equal('200', headers:get(":status"))

    assert.is_table(json.database)
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
end

describe("/status provides config_hash", function()
  lazy_setup(function()
    helpers.get_db_utils("off", {
      "plugins",
      "services",
    })
    assert(helpers.start_kong {
      status_listen = "127.0.0.1:9500",
      database = "off",
    })
  end)

  lazy_teardown(function()
    helpers.stop_kong()
  end)

 it("once an initial configuration has been pushed in dbless mode #off", function()
   local admin_client = helpers.http_client("127.0.0.1", 9001)
   -- push an initial configuration so that a configuration_hash will be present
   local postres = assert(admin_client:send {
     method = "POST",
     path = "/config",
     body = {
       config = [[
_format_version: "3.0"
services:
 - name: example-service
   url: http://example.test
]],
      },
      headers = {
        ["Content-Type"] = "application/json"
      }
    })
    assert.res_status(201, postres)
    admin_client:close()
    local client = helpers.http_client("127.0.0.1", 9500)
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
    assert.is_string(json.configuration_hash)
    assert.equal(32, #json.configuration_hash)
    client:close()
  end)
end)

