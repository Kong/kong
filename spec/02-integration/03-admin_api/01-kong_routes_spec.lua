local helpers = require "spec.helpers"
local cjson = require "cjson"

describe("Admin API", function()
  local client
  setup(function()
    helpers.prepare_prefix()
    assert(helpers.start_kong())

    client = helpers.admin_client(10000)
  end)
  teardown(function()
    if client then client:close() end
    assert(helpers.stop_kong())
    helpers.clean_prefix()
  end)

  describe("Kong routes", function()
    describe("/", function()
      local meta = require "kong.meta"

      it("returns Kong's version number and tagline", function()
        local res = assert(client:send {
          method = "GET",
          path = "/"
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.equal(meta._VERSION, json.version)
        assert.equal("Welcome to kong", json.tagline)
      end)
      it("response has the correct Server header", function()
        local res = assert(client:send {
          method = "GET",
          path = "/"
        })
        assert.res_status(200, res)
        assert.equal(string.format("%s/%s", meta._NAME, meta._VERSION), res.headers.server)
        assert.is_nil(res.headers.via) -- Via is only set for proxied requests
      end)
      it("returns 405 on invalid method", function()
        local methods = {"POST", "PUT", "DELETE", "PATCH"}
        for i = 1, #methods do
          local res = assert(client:send {
            method = methods[i],
            path = "/",
            body = {}, -- tmp: body to allow POST/PUT to work
            headers = {["Content-Type"] = "application/json"}
          })
          local body = assert.response(res).has.status(405)
          assert.equal([[{"message":"Method not allowed"}]], body)
        end
      end)
    end)
  end)

  describe("/status", function()
    it("returns status info", function()
      local res = assert(client:send {
        method = "GET",
        path = "/status"
      })
      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      assert.is_table(json.database)
      assert.is_table(json.server)

      for k in pairs(helpers.dao.daos) do
        assert.is_number(json.database[k])
      end

      assert.is_number(json.server.connections_accepted)
      assert.is_number(json.server.connections_active)
      assert.is_number(json.server.connections_handled)
      assert.is_number(json.server.connections_reading)
      assert.is_number(json.server.connections_writing)
      assert.is_number(json.server.connections_waiting)
      assert.is_number(json.server.total_requests)
    end)
  end)

  describe("request size", function()
    setup(function()
      assert(helpers.dao.apis:insert {
        name = "my-api",
        request_host = "my.api.com",
        upstream_url = "http://api.com"
      })
    end)
    it("handles req bodies < 10MB", function()
      local ip = "204.48.16.0"
      local n = 2^20 / #ip
      local buf = {}
      for i = 1, n do buf[#buf+1] = ip end
      local ips = table.concat(buf, ",")

      local res = assert(client:send {
        method = "POST",
        path = "/apis/my-api/plugins",
        body = {
          name = "ip-restriction",
          ["config.blacklist"] = ips
        },
        headers = {["Content-Type"] = "application/json"}
      })
      assert.res_status(201, res)
    end)
    it("fails with req bodies 10MB", function()
      local ip = "204.48.16.0"
      local n = 11 * 2^20 / #ip
      local buf = {}
      for i = 1, n do buf[#buf+1] = ip end
      local ips = table.concat(buf, ",")

      local res = assert(client:send {
        method = "POST",
        path = "/apis/my-api/plugins",
        body = {
          name = "ip-restriction",
          ["config.blacklist"] = ips
        },
        headers = {["Content-Type"] = "application/json"}
      })
      assert.res_status(413, res)
    end)
  end)
end)
