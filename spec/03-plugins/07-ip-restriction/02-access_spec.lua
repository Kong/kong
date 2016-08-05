local helpers = require "spec.helpers"
local cache = require "kong.tools.database_cache"
local cjson = require "cjson"

describe("Plugin: ip-restriction (access)", function()
  local plugin_config
  local client, admin_client
  setup(function()
    assert(helpers.start_kong())
    client = helpers.proxy_client()
    admin_client = helpers.admin_client()

    local api1 = assert(helpers.dao.apis:insert {
      request_host = "ip-restriction1.com",
      upstream_url = "http://mockbin.com"
    })
    assert(helpers.dao.plugins:insert {
      name = "ip-restriction",
      api_id = api1.id,
      config = {
        blacklist = {"127.0.0.1", "127.0.0.2"}
      }
    })

    local api2 = assert(helpers.dao.apis:insert {
      request_host = "ip-restriction2.com",
      upstream_url = "http://mockbin.com"
    })
    plugin_config = assert(helpers.dao.plugins:insert {
      name = "ip-restriction",
      api_id = api2.id,
      config = {
        blacklist = {"127.0.0.2"}
      }
    })

    local api3 = assert(helpers.dao.apis:insert {
      request_host = "ip-restriction3.com",
      upstream_url = "http://mockbin.com"
    })
    assert(helpers.dao.plugins:insert {
      name = "ip-restriction",
      api_id = api3.id,
      config = {
        whitelist = {"127.0.0.2"}
      }
    })
    local api4 = assert(helpers.dao.apis:insert {
      request_host = "ip-restriction4.com",
      upstream_url = "http://mockbin.com"
    })
    assert(helpers.dao.plugins:insert {
      name = "ip-restriction",
      api_id = api4.id,
      config = {
        whitelist = {"127.0.0.1"}
      }
    })

    local api5 = assert(helpers.dao.apis:insert {
      request_host = "ip-restriction5.com",
      upstream_url = "http://mockbin.com"
    })
    assert(helpers.dao.plugins:insert {
      name = "ip-restriction",
      api_id = api5.id,
      config = {
        blacklist = {"127.0.0.0/24"}
      }
    })
  end)
  teardown(function()
    if client and admin_client then
      client:close()
      admin_client:close()
    end
    helpers.stop_kong()
  end)

  describe("blacklist", function()
    it("blocks a request when the IP is blacklisted", function()
      local res = assert(client:send {
        method = "GET",
        path = "/status/200",
        headers = {
          ["Host"] = "ip-restriction1.com"
        }
      })
      local body = assert.res_status(403, res)
      assert.equal([[{"message":"Your IP address is not allowed"}]], body)
    end)
    it("allows a request when the IP is not blacklisted", function()
      local res = assert(client:send {
        method = "GET",
        path = "/request",
        headers = {
          ["Host"] = "ip-restriction2.com"
        }
      })
      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      assert.equal("127.0.0.1", json.clientIPAddress)
    end)
    it("blocks IP with CIDR", function()
      local res = assert(client:send {
        method = "GET",
        path = "/status/200",
        headers = {
          ["Host"] = "ip-restriction5.com"
        }
      })
      local body = assert.res_status(403, res)
      assert.equal([[{"message":"Your IP address is not allowed"}]], body)
    end)
  end)

  describe("whitelist", function()
    it("blocks a request when the IP is not whitelisted", function()
      local res = assert(client:send {
        method = "GET",
        path = "/status/200",
        headers = {
          ["Host"] = "ip-restriction3.com"
        }
      })
      local body = assert.res_status(403, res)
      assert.equal([[{"message":"Your IP address is not allowed"}]], body)
    end)
    it("allows a whitelisted IP", function()
      local res = assert(client:send {
        method = "GET",
        path = "/status/200",
        headers = {
          ["Host"] = "ip-restriction4.com"
        }
      })
      assert.res_status(200, res)
    end)
  end)

  it("supports config changes without restarting", function()
    local res = assert(client:send {
      method = "GET",
      path = "/request",
      headers = {
        ["Host"] = "ip-restriction2.com"
      }
    })
    assert.res_status(200, res)

    res = assert(admin_client:send {
      method = "PATCH",
      path = "/apis/ip-restriction2.com/plugins/"..plugin_config.id,
      body = {
        ["config.blacklist"] = "127.0.0.1,127.0.0.2"
      },
      headers = {
        ["Content-Type"] = "application/json"
      }
    })
    assert.res_status(200, res)

    local cache_key = cache.plugin_key(plugin_config.name, plugin_config.api_id, plugin_config.consumer_id)

    helpers.wait_until(function()
      res = assert(admin_client:send {
        method = "GET",
        path = "/cache/"..cache_key
      })
      res:read_body()
      return res.status ~= 200
    end)

    local res = assert(client:send {
      method = "GET",
      path = "/request",
      headers = {
        ["Host"] = "ip-restriction2.com"
      }
    })
    local body = assert.res_status(403, res)
    assert.equal([[{"message":"Your IP address is not allowed"}]], body)
  end)
end)
