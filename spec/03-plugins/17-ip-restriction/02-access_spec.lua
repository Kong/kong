local helpers = require "spec.helpers"
local cjson   = require "cjson"


for _, strategy in helpers.each_strategy() do
  describe("Plugin: ip-restriction (access) [#" .. strategy .. "]", function()
    local plugin
    local proxy_client
    local admin_client
    local db

    lazy_setup(function()
      local bp
      bp, db = helpers.get_db_utils(strategy, {
        "routes",
        "services",
        "plugins",
      })

      local route1 = bp.routes:insert {
        hosts = { "ip-restriction1.com" },
      }

      local route2 = bp.routes:insert {
        hosts = { "ip-restriction2.com" },
      }

      local route3 = bp.routes:insert {
        hosts = { "ip-restriction3.com" },
      }

      local route4 = bp.routes:insert {
        hosts = { "ip-restriction4.com" },
      }

      local route5 = bp.routes:insert {
        hosts = { "ip-restriction5.com" },
      }

      local route6 = bp.routes:insert {
        hosts = { "ip-restriction6.com" },
      }

      local route7 = bp.routes:insert {
        hosts = { "ip-restriction7.com" },
      }

      local route8 = bp.routes:insert {
        hosts = { "ip-restriction8.com" },
      }

      bp.plugins:insert {
        name     = "ip-restriction",
        route = { id = route1.id },
        config   = {
          blacklist = { "127.0.0.1", "127.0.0.2" }
        },
      }

      plugin = assert(db.plugins:insert {
        name     = "ip-restriction",
        route = { id = route2.id },
        config   = {
          blacklist = { "127.0.0.2" },
        },
      })

      assert(db.plugins:insert {
        name     = "ip-restriction",
        route = { id = route3.id },
        config   = {
          whitelist = { "127.0.0.2" },
        },
      })

      assert(db.plugins:insert {
        name     = "ip-restriction",
        route = { id = route4.id },
        config   = {
          whitelist = { "127.0.0.1" },
        },
      })

      assert(db.plugins:insert {
        name     = "ip-restriction",
        route = { id = route5.id },
        config   = {
          blacklist = { "127.0.0.0/24" },
        },
      })

      assert(db.plugins:insert {
        name     = "ip-restriction",
        route = { id = route6.id },
        config   = {
          whitelist = { "127.0.0.4" },
        },
      })

      assert(db.plugins:insert {
        name     = "ip-restriction",
        route = { id = route7.id },
        config   = {
          blacklist = { "127.0.0.4" },
        },
      })

      assert(db.plugins:insert {
        name     = "ip-restriction",
        route = { id = route8.id },
        config   = {
          whitelist = { "0.0.0.0/0" },
        },
      })

      assert(helpers.start_kong {
        database          = strategy,
        real_ip_header    = "X-Forwarded-For",
        real_ip_recursive = "on",
        trusted_ips       = "0.0.0.0/0, ::/0",
        nginx_conf        = "spec/fixtures/custom_nginx.template",
      })

      proxy_client = helpers.proxy_client()
      admin_client = helpers.admin_client()
    end)

    lazy_teardown(function()
      if proxy_client and admin_client then
        proxy_client:close()
        admin_client:close()
      end

      helpers.stop_kong()
    end)

    describe("blacklist", function()
      it("blocks a request when the IP is blacklisted", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/status/200",
          headers = {
            ["Host"] = "ip-restriction1.com"
          }
        })
        local body = assert.res_status(403, res)
        local json = cjson.decode(body)
        assert.same({ message = "Your IP address is not allowed" }, json)
      end)
      it("allows a request when the IP is not blacklisted", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          headers = {
            ["Host"] = "ip-restriction2.com"
          }
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.equal("127.0.0.1", json.vars.remote_addr)
      end)
      it("blocks IP with CIDR", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/status/200",
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
          local res = assert(proxy_client:send {
            method  = "GET",
            path    = "/request",
            headers = {
              ["Host"] = "ip-restriction7.com"
            }
          })
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)
          assert.equal("127.0.0.1", json.vars.remote_addr)
        end)
        it("allows with allowed X-Forwarded-For header", function()
          local res = assert(proxy_client:send {
            method  = "GET",
            path    = "/request",
            headers = {
              ["Host"]            = "ip-restriction7.com",
              ["X-Forwarded-For"] = "127.0.0.3"
            }
          })
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)
          assert.equal("127.0.0.3", json.vars.remote_addr)
        end)
        it("blocks with not allowed X-Forwarded-For header", function()
          local res = assert(proxy_client:send {
            method  = "GET",
            path    = "/status/200",
            headers = {
              ["Host"]            = "ip-restriction7.com",
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
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/status/200",
          headers = {
            ["Host"] = "ip-restriction3.com"
          }
        })
        local body = assert.res_status(403, res)
        local json = cjson.decode(body)
        assert.same({ message = "Your IP address is not allowed" }, json)
      end)
      it("allows a whitelisted IP", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/status/200",
          headers = {
            ["Host"] = "ip-restriction4.com"
          }
        })
        assert.res_status(200, res)
      end)

      describe("X-Forwarded-For", function()
        it("blocks without any X-Forwarded-For and not allowed IP", function()
          local res = assert(proxy_client:send {
            method  = "GET",
            path    = "/status/200",
            headers = {
              ["Host"] = "ip-restriction6.com"
            }
          })
          local body = assert.res_status(403, res)
          local json = cjson.decode(body)
          assert.same({ message = "Your IP address is not allowed" }, json)
        end)
        it("block with not allowed X-Forwarded-For header", function()
          local res = assert(proxy_client:send {
            method  = "GET",
            path    = "/status/200",
            headers = {
              ["Host"]            = "ip-restriction6.com",
              ["X-Forwarded-For"] = "127.0.0.3"
            }
          })
          local body = assert.res_status(403, res)
          local json = cjson.decode(body)
          assert.same({ message = "Your IP address is not allowed" }, json)
        end)
        it("allows with allowed X-Forwarded-For header", function()
          local res = assert(proxy_client:send {
            method  = "GET",
            path    = "/status/200",
            headers = {
              ["Host"]            = "ip-restriction6.com",
              ["X-Forwarded-For"] = "127.0.0.4"
            }
          })
          assert.res_status(200, res)
        end)
        it("allows with allowed complex X-Forwarded-For header", function()
          local res = assert(proxy_client:send {
            method  = "GET",
            path    = "/status/200",
            headers = {
              ["Host"]            = "ip-restriction6.com",
              ["X-Forwarded-For"] = "127.0.0.4, 127.0.0.3"
            }
          })
          assert.res_status(200, res)
        end)
      end)
    end)

    it("supports config changes without restarting", function()
      local res = assert(proxy_client:send {
        method  = "GET",
        path    = "/request",
        headers = {
          ["Host"] = "ip-restriction2.com"
        }
      })
      assert.res_status(200, res)

      res = assert(admin_client:send {
        method  = "PATCH",
        path    = "/plugins/" .. plugin.id,
        body    = {
          config = { blacklist = { "127.0.0.1", "127.0.0.2" } },
        },
        headers = {
          ["Content-Type"] = "application/json"
        }
      })
      assert.res_status(200, res)

      local cache_key = db.plugins:cache_key(plugin)

      helpers.wait_for_invalidation(cache_key)

      local res = assert(proxy_client:send {
        method  = "GET",
        path    = "/request",
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
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/status/200",
          headers = {
            ["Host"] = "ip-restriction8.com"
          }
        })
        assert.res_status(200, res)
      end)
    end)
  end)
end
