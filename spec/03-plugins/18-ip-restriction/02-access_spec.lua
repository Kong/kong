local helpers = require "spec.helpers"
local cache = require "kong.tools.database_cache"
local cjson = require "cjson"

describe("Plugin: ip-restriction (access)", function()
  local plugin_config
  local client, admin_client

  setup(function()
    local api1 = assert(helpers.dao.apis:insert {
      name = "api-1",
      hosts = { "ip-restriction1.com" },
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
      name = "api-2",
      hosts = { "ip-restriction2.com" },
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
      name = "api-3",
      hosts = { "ip-restriction3.com" },
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
      name = "api-4",
      hosts = { "ip-restriction4.com" },
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
      name = "api-5",
      hosts = { "ip-restriction5.com" },
      upstream_url = "http://mockbin.com"
    })
    assert(helpers.dao.plugins:insert {
      name = "ip-restriction",
      api_id = api5.id,
      config = {
        blacklist = {"127.0.0.0/24"}
      }
    })

    local api6 = assert(helpers.dao.apis:insert {
      name = "api-6",
      hosts = { "ip-restriction6.com" },
      upstream_url = "http://mockbin.com"
    })
    assert(helpers.dao.plugins:insert {
      name = "ip-restriction",
      api_id = api6.id,
      config = {
        whitelist = {"127.0.0.4"}
      }
    })

    local api7 = assert(helpers.dao.apis:insert {
      name = "api-7",
      hosts = { "ip-restriction7.com" },
      upstream_url = "http://mockbin.com"
    })
    assert(helpers.dao.plugins:insert {
      name = "ip-restriction",
      api_id = api7.id,
      config = {
        blacklist = {"127.0.0.4"}
      }
    })

    assert(helpers.start_kong())
    client = helpers.proxy_client()
    admin_client = helpers.admin_client()
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
      local json = cjson.decode(body)
      assert.same({ message = "Your IP address is not allowed" }, json)
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
      local json = cjson.decode(body)
      assert.same({ message = "Your IP address is not allowed" }, json)
    end)

    describe("X-Forwarded-For", function()
      it("allows without any X-Forwarded-For and allowed IP", function()
        local res = assert(client:send {
          method = "GET",
          path = "/request",
          headers = {
            ["Host"] = "ip-restriction7.com"
          }
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.equal("127.0.0.1", json.clientIPAddress)
      end)
      it("allows with allowed X-Forwarded-For header", function()
        local res = assert(client:send {
          method = "GET",
          path = "/request",
          headers = {
            ["Host"] = "ip-restriction7.com",
            ["X-Forwarded-For"] = "127.0.0.3"
          }
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.equal("127.0.0.3", json.clientIPAddress)
      end)
      it("blocks with not allowed X-Forwarded-For header", function()
        local res = assert(client:send {
          method = "GET",
          path = "/status/200",
          headers = {
            ["Host"] = "ip-restriction7.com",
            ["X-Forwarded-For"] = "127.0.0.4"
          }
        })
        local body = assert.res_status(403, res)
        local json = cjson.decode(body)
        assert.same({ message = "Your IP address is not allowed" }, json)
      end)
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
      local json = cjson.decode(body)
      assert.same({ message = "Your IP address is not allowed" }, json)
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

    describe("X-Forwarded-For", function()
      it("blocks without any X-Forwarded-For and not allowed IP", function()
        local res = assert(client:send {
          method = "GET",
          path = "/status/200",
          headers = {
            ["Host"] = "ip-restriction6.com"
          }
        })
        local body = assert.res_status(403, res)
        local json = cjson.decode(body)
        assert.same({ message = "Your IP address is not allowed" }, json)
      end)
      it("block with not allowed X-Forwarded-For header", function()
        local res = assert(client:send {
          method = "GET",
          path = "/status/200",
          headers = {
            ["Host"] = "ip-restriction6.com",
            ["X-Forwarded-For"] = "127.0.0.3"
          }
        })
        local body = assert.res_status(403, res)
        local json = cjson.decode(body)
        assert.same({ message = "Your IP address is not allowed" }, json)
      end)
      it("allows with allowed X-Forwarded-For header", function()
        local res = assert(client:send {
          method = "GET",
          path = "/status/200",
          headers = {
            ["Host"] = "ip-restriction6.com",
            ["X-Forwarded-For"] = "127.0.0.4"
          }
        })
        assert.res_status(200, res)
      end)
      it("allows with allowed complex X-Forwarded-For header", function()
        local res = assert(client:send {
          method = "GET",
          path = "/status/200",
          headers = {
            ["Host"] = "ip-restriction6.com",
            ["X-Forwarded-For"] = "127.0.0.4, 127.0.0.3"
          }
        })
        assert.res_status(200, res)
      end)
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
      path = "/apis/api-2/plugins/"..plugin_config.id,
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
    local json = cjson.decode(body)
    assert.same({ message = "Your IP address is not allowed" }, json)
  end)
end)
