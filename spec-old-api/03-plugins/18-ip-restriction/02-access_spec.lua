local helpers = require "spec.helpers"
local cjson = require "cjson"

describe("Plugin: ip-restriction (access)", function()
  local plugin_config
  local client, admin_client
  local dao, db, _

  lazy_setup(function()
    _, db, dao = helpers.get_db_utils()

    local api1 = assert(dao.apis:insert {
      name         = "api-1",
      hosts        = { "ip-restriction1.com" },
      upstream_url = helpers.mock_upstream_url,
    })
    assert(db.plugins:insert {
      name   = "ip-restriction",
      api = { id = api1.id },
      config = {
        blacklist = {"127.0.0.1", "127.0.0.2"}
      },
    })

    local api2 = assert(dao.apis:insert {
      name         = "api-2",
      hosts        = { "ip-restriction2.com" },
      upstream_url = helpers.mock_upstream_url,
    })
    plugin_config = assert(db.plugins:insert {
      name   = "ip-restriction",
      api = { id = api2.id },
      config = {
        blacklist = {"127.0.0.2"},
      },
    })

    local api3 = assert(dao.apis:insert {
      name         = "api-3",
      hosts        = { "ip-restriction3.com" },
      upstream_url = helpers.mock_upstream_url,
    })
    assert(db.plugins:insert {
      name   = "ip-restriction",
      api = { id = api3.id },
      config = {
        whitelist = {"127.0.0.2"},
      },
    })
    local api4 = assert(dao.apis:insert {
      name         = "api-4",
      hosts        = { "ip-restriction4.com" },
      upstream_url = helpers.mock_upstream_url,
    })
    assert(db.plugins:insert {
      name   = "ip-restriction",
      api = { id = api4.id },
      config = {
        whitelist = {"127.0.0.1"},
      },
    })

    local api5 = assert(dao.apis:insert {
      name         = "api-5",
      hosts        = { "ip-restriction5.com" },
      upstream_url = helpers.mock_upstream_url,
    })
    assert(db.plugins:insert {
      name   = "ip-restriction",
      api = { id = api5.id },
      config = {
        blacklist = {"127.0.0.0/24"},
      },
    })

    local api6 = assert(dao.apis:insert {
      name         = "api-6",
      hosts        = { "ip-restriction6.com" },
      upstream_url = helpers.mock_upstream_url,
    })
    assert(db.plugins:insert {
      name   = "ip-restriction",
      api = { id = api6.id },
      config = {
        whitelist = {"127.0.0.4"},
      },
    })

    local api7 = assert(dao.apis:insert {
      name         = "api-7",
      hosts        = { "ip-restriction7.com" },
      upstream_url = helpers.mock_upstream_url,
    })
    assert(db.plugins:insert {
      name   = "ip-restriction",
      api = { id = api7.id },
      config = {
        blacklist = {"127.0.0.4"},
      },
    })

    local api8 = assert(dao.apis:insert {
      name         = "api-8",
      hosts        = { "ip-restriction8.com" },
      upstream_url = helpers.mock_upstream_url,
    })
    assert(db.plugins:insert {
      name   = "ip-restriction",
      api = { id = api8.id },
      config = {
        whitelist = { "0.0.0.0/0" },
      },
    })

    assert(helpers.start_kong {
      real_ip_header    = "X-Forwarded-For",
      real_ip_recursive = "on",
      trusted_ips       = "0.0.0.0/0, ::/0",
      nginx_conf        = "spec/fixtures/custom_nginx.template",
    })
    client = helpers.proxy_client()
    admin_client = helpers.admin_client()
  end)

  lazy_teardown(function()
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
      assert.equal("127.0.0.1", json.vars.remote_addr)
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
        assert.equal("127.0.0.1", json.vars.remote_addr)
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
        assert.equal("127.0.0.3", json.vars.remote_addr)
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
      path = "/apis/api-2/plugins/" .. plugin_config.id,
      body = {
        ["config.blacklist"] = { "127.0.0.1", "127.0.0.2" }
      },
      headers = {
        ["Content-Type"] = "application/json"
      }
    })
    assert.res_status(200, res)

    local cache_key = db.plugins:cache_key(plugin_config.name,
                                           nil, nil,
                                           plugin_config.api.id,
                                           nil)

    helpers.wait_until(function()
      res = assert(admin_client:send {
        method = "GET",
        path = "/cache/" .. cache_key
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

  describe("#regression", function()
    it("handles a CIDR entry with 0.0.0.0/0", function()
      local res = assert(client:send {
        method = "GET",
        path = "/status/200",
        headers = {
          ["Host"] = "ip-restriction8.com"
        }
      })
      assert.res_status(200, res)
    end)
  end)
end)
