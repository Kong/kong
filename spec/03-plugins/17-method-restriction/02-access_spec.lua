local helpers = require "spec.helpers"
local cjson = require "cjson"

describe("Plugin: method-restriction (access)", function()
  local client
  setup(function()
    assert(helpers.start_kong())
    client = helpers.proxy_client()

    local api1 = assert(helpers.dao.apis:insert {
      request_host = "mr1.com",
      upstream_url = "http://mockbin.com"
    })
    local api2 = assert(helpers.dao.apis:insert {
      request_host = "mr2.com",
      upstream_url = "http://mockbin.com"
    })
    local api3 = assert(helpers.dao.apis:insert {
      request_host = "mr3.com",
      upstream_url = "http://mockbin.com"
    })
    local api4 = assert(helpers.dao.apis:insert {
      request_host = "mr4.com",
      upstream_url = "http://mockbin.com"
    })
    local api5 = assert(helpers.dao.apis:insert {
      request_host = "mr5.com",
      upstream_url = "http://mockbin.com"
    })

    assert(helpers.dao.plugins:insert {
      name = "method-restriction",
      api_id = api1.id,
      config = {
        blacklist = {"GET"}
      }
    })
    assert(helpers.dao.plugins:insert {
      name = "method-restriction",
      api_id = api2.id,
      config = {
        blacklist = {"POST"}
      }
    })
    assert(helpers.dao.plugins:insert {
      name = "method-restriction",
      api_id = api3.id,
      config = {
        whitelist = {"GET"}
      }
    })
    assert(helpers.dao.plugins:insert {
      name = "method-restriction",
      api_id = api4.id,
      config = {
        whitelist = {"POST"}
      }
    })
    assert(helpers.dao.plugins:insert {
      name = "method-restriction",
      api_id = api5.id,
      config = {
        whitelist = {"Get"}
      }
    })
  end)

  teardown(function()
    if client then client:close() end
    helpers.stop_kong()
  end)

  describe("blacklist", function()
    it("blocks a request when the method is blacklisted", function()
      local res = assert(client:send {
        method = "GET",
        path = "/status/200",
        headers = {
          ["Host"] = "mr1.com"
        }
      })
      local body = assert.res_status(405, res)
      assert.equal([[{"message":"Method not allowed"}]], body)
    end)
    it("allows a request when the method is not blacklisted", function()
      local res = assert(client:send {
        method = "GET",
        path = "/request",
        headers = {
          ["Host"] = "mr2.com"
        }
      })
      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      assert.equal("GET", json.method)
    end)
  end)

  describe("whitelist", function()
    it("blocks a request when the method is not whitelisted", function()
      local res = assert(client:send {
        method = "POST",
        path = "/status/200",
        headers = {
          ["Host"] = "mr3.com"
        }
      })
      local body = assert.res_status(405, res)
      assert.equal([[{"message":"Method not allowed"}]], body)
    end)
    it("allows a request when the method is whitelisted", function()
      local res = assert(client:send {
        method = "POST",
        path = "/status/200",
        headers = {
          ["Host"] = "mr4.com"
        }
      })
      assert.res_status(200, res)
    end)
    it("allows a request when method is registered with camelcase", function()
      local res = assert(client:send {
        method = "GET",
        path = "/status/200",
        headers = {
          ["Host"] = "mr5.com"
        }
      })
      assert.res_status(200, res)
    end)
  end)

end)
