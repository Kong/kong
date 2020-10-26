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

      local route9 = bp.routes:insert {
        hosts = { "ip-restriction9.com" },
      }

      local route10 = bp.routes:insert {
        hosts = { "ip-restriction10.com" },
      }

      local route11 = bp.routes:insert {
        hosts = { "ip-restriction11.com" },
      }

      local grpc_service = bp.services:insert {
          name = "grpc1",
          url = "grpc://localhost:15002",
      }

      local route_grpc_deny = assert(bp.routes:insert {
        protocols = { "grpc" },
        paths = { "/hello.HelloService/" },
        hosts = { "ip-restriction-grpc1.com" },
        service = grpc_service,
      })

      local route_grpc_allow = assert(bp.routes:insert {
        protocols = { "grpc" },
        paths = { "/hello.HelloService/" },
        hosts = { "ip-restriction-grpc2.com" },
        service = grpc_service,
      })

      local route_grpc_xforwarded_deny = assert(bp.routes:insert {
        protocols = { "grpc" },
        paths = { "/hello.HelloService/" },
        hosts = { "ip-restriction-grpc3.com" },
        service = grpc_service,
      })

      bp.plugins:insert {
        name     = "ip-restriction",
        route = { id = route1.id },
        config   = {
          deny = { "127.0.0.1", "127.0.0.2" }
        },
      }

      plugin = assert(db.plugins:insert {
        name     = "ip-restriction",
        route = { id = route2.id },
        config   = {
          deny = { "127.0.0.2" },
        },
      })

      assert(db.plugins:insert {
        name     = "ip-restriction",
        route = { id = route3.id },
        config   = {
          allow = { "127.0.0.2" },
        },
      })

      assert(db.plugins:insert {
        name     = "ip-restriction",
        route = { id = route4.id },
        config   = {
          allow = { "127.0.0.1" },
        },
      })

      assert(db.plugins:insert {
        name     = "ip-restriction",
        route = { id = route5.id },
        config   = {
          deny = { "127.0.0.0/24" },
        },
      })

      assert(db.plugins:insert {
        name     = "ip-restriction",
        route = { id = route6.id },
        config   = {
          allow = { "127.0.0.4" },
        },
      })

      assert(db.plugins:insert {
        name     = "ip-restriction",
        route = { id = route7.id },
        config   = {
          deny = { "127.0.0.4" },
        },
      })

      assert(db.plugins:insert {
        name     = "ip-restriction",
        route = { id = route8.id },
        config   = {
          allow = { "0.0.0.0/0" },
        },
      })

      assert(db.plugins:insert {
        name     = "ip-restriction",
        route = { id = route9.id },
        config   = {
          allow = { "127.0.0.1" },
          deny = { "127.0.0.1" },
        },
      })

      assert(db.plugins:insert {
        name     = "ip-restriction",
        route = { id = route10.id },
        config   = {
          allow = { "127.0.0.0/24" },
          deny = { "127.0.0.1" },
        },
      })

      assert(db.plugins:insert {
        name     = "ip-restriction",
        route = { id = route11.id },
        config   = {
          allow = { "127.0.0.0/24" },
          deny = { "127.0.0.0/24" },
        },
      })

      assert(db.plugins:insert {
        name     = "ip-restriction",
        route = { id = route_grpc_deny.id },
        config   = {
          deny = { "127.0.0.1", "127.0.0.2" }
        },
      })

      assert(db.plugins:insert {
        name     = "ip-restriction",
        route = { id = route_grpc_allow.id },
        config   = {
          deny = { "127.0.0.2" }
        },
      })

      assert(db.plugins:insert {
        name     = "ip-restriction",
        route = { id = route_grpc_xforwarded_deny.id },
        config   = {
          allow = { "127.0.0.4" },
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

    describe("deny", function()
      it("blocks a request when the IP is denied", function()
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

      it("blocks a request when the IP is denied #grpc", function()
        local ok, err =   helpers.proxy_client_grpc(){
          service = "hello.HelloService.SayHello",
          opts = {
            ["-authority"] = "ip-restriction-grpc1.com",
            ["-v"] = true,
          },
        }
        assert.falsy(ok)
        assert.matches("Code: PermissionDenied", err)
      end)

      it("allows a request when the IP is not denied", function()
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

      it("allows a request when the IP is not denied #grpc", function()
        local ok = helpers.proxy_client_grpc(){
          service = "hello.HelloService.SayHello",
          opts = {
            ["-authority"] = "ip-restriction-grpc2.com",
            ["-v"] = true,
          },
        }
        assert.truthy(ok)
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
      it("blocks an IP on a allowed CIDR range", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/status/200",
          headers = {
            ["Host"] = "ip-restriction10.com"
          }
        })
        local body = assert.res_status(403, res)
        local json = cjson.decode(body)
        assert.same({ message = "Your IP address is not allowed" }, json)
      end)
      it("takes precedence over an allowed IP", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/status/200",
          headers = {
            ["Host"] = "ip-restriction9.com"
          }
        })
        local body = assert.res_status(403, res)
        local json = cjson.decode(body)
        assert.same({ message = "Your IP address is not allowed" }, json)
      end)
      it("takes precedence over an allowed CIDR range", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/status/200",
          headers = {
            ["Host"] = "ip-restriction11.com"
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

    describe("allow", function()
      it("blocks a request when the IP is not allowed", function()
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
      it("allows a allowed IP", function()
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
        it("block with not allowed X-Forwarded-For header #grpc", function()
          local ok, err = helpers.proxy_client_grpc(){
            service = "hello.HelloService.SayHello",
            opts = {
              ["-authority"] = "ip-restriction-grpc3.com",
              ["-v"] = true,
            },
          }
          assert.falsy(ok)
          assert.matches("Code: PermissionDenied", err)
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
        it("allows with allowed X-Forwarded-For header #grpc", function()
          assert.truthy(helpers.proxy_client_grpc(){
            service = "hello.HelloService.SayHello",
            opts = {
              ["-authority"] = "ip-restriction-grpc3.com",
              ["-v"] = true,
              ["-H"] = "'X-Forwarded-For: 127.0.0.4'",
            },
          })
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
          config = { deny = { "127.0.0.1", "127.0.0.2" } },
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

      local route9 = bp.routes:insert {
        hosts = { "ip-restriction9.com" },
      }

      bp.plugins:insert {
        name     = "ip-restriction",
        route = { id = route1.id },
        config   = {
          deny = { "::1", "::2" }
        },
      }

      plugin = assert(db.plugins:insert {
        name     = "ip-restriction",
        route = { id = route2.id },
        config   = {
          deny = { "::2" },
        },
      })

      assert(db.plugins:insert {
        name     = "ip-restriction",
        route = { id = route3.id },
        config   = {
          deny = { "fe80::/8" },
        },
      })


      assert(db.plugins:insert {
        name     = "ip-restriction",
        route = { id = route4.id },
        config   = {
          allow = { "::2" },
        },
      })

      assert(db.plugins:insert {
        name     = "ip-restriction",
        route = { id = route5.id },
        config   = {
          allow = { "::1" },
        },
      })

      assert(db.plugins:insert {
        name     = "ip-restriction",
        route = { id = route6.id },
        config   = {
          allow = { "::/0" },
        },
      })

      assert(db.plugins:insert {
        name     = "ip-restriction",
        route = { id = route7.id },
        config   = {
          allow = { "::1" },
          deny = { "::1" },
        },
      })

      assert(db.plugins:insert {
        name     = "ip-restriction",
        route = { id = route8.id },
        config   = {
          allow = { "::1/128" },
          deny = { "::1" },
        },
      })

      assert(db.plugins:insert {
        name     = "ip-restriction",
        route = { id = route9.id },
        config   = {
          allow = { "::1/128" },
          deny = { "::1/128" },
        },
      })

      assert(helpers.start_kong {
        database          = strategy,
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

    describe("deny", function()
      it("blocks a request when the IPv6 is denied", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/status/200",
          headers = {
            ["Host"] = "ip-restriction1.com",
            ["X-Real-IP"] = "::1",
          }
        })
        local body = assert.res_status(403, res)
        local json = cjson.decode(body)
        assert.same({ message = "Your IP address is not allowed" }, json)
      end)
      it("allows a request when the IPv6 is not denied", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          headers = {
            ["Host"] = "ip-restriction2.com",
            ["X-Real-IP"] = "::1",
          }
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.equal("::1", json.vars.remote_addr)
      end)
      it("blocks the IPv6 with CIDR", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/status/200",
          headers = {
            ["Host"] = "ip-restriction3.com",
            ["X-Real-IP"] = "fe80::1",
          }
        })
        local body = assert.res_status(403, res)
        local json = cjson.decode(body)
        assert.same({ message = "Your IP address is not allowed" }, json)
      end)
      it("blocks an IPv6 on a allowed IPv6 CIDR range", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/status/200",
          headers = {
            ["Host"] = "ip-restriction8.com",
            ["X-Real-IP"] = "::1",
          }
        })
        local body = assert.res_status(403, res)
        local json = cjson.decode(body)
        assert.same({ message = "Your IP address is not allowed" }, json)
      end)
      it("takes precedence over an allowed IPv6", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/status/200",
          headers = {
            ["Host"] = "ip-restriction7.com",
            ["X-Real-IP"] = "::1",
          }
        })
        local body = assert.res_status(403, res)
        local json = cjson.decode(body)
        assert.same({ message = "Your IP address is not allowed" }, json)
      end)
      it("takes precedence over an allowed IPv6 CIDR range", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/status/200",
          headers = {
            ["Host"] = "ip-restriction9.com"
          }
        })
        local body = assert.res_status(403, res)
        local json = cjson.decode(body)
        assert.same({ message = "Your IP address is not allowed" }, json)
      end)
    end)

    describe("allow", function()
      it("blocks a request when the IPv6 is not allowed", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/status/200",
          headers = {
            ["Host"] = "ip-restriction4.com",
            ["X-Real-IP"] = "::1",
          }
        })
        local body = assert.res_status(403, res)
        local json = cjson.decode(body)
        assert.same({ message = "Your IP address is not allowed" }, json)
      end)
      it("allows a allowed IPv6", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/status/200",
          headers = {
            ["Host"] = "ip-restriction5.com",
            ["X-Real-IP"] = "::1",
          }
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.equal("::1", json.vars.remote_addr)
      end)
    end)

    it("supports config changes without restarting", function()
      local res = assert(proxy_client:send {
        method  = "GET",
        path    = "/request",
        headers = {
          ["Host"] = "ip-restriction2.com",
          ["X-Real-IP"] = "::1",
        }
      })
      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      assert.equal("::1", json.vars.remote_addr)

      res = assert(admin_client:send {
        method  = "PATCH",
        path    = "/plugins/" .. plugin.id,
        body    = {
          config = { deny = { "::1", "::2" } },
        },
        headers = {
          ["Content-Type"] = "application/json"
        }
      })
      assert.res_status(200, res)

      local cache_key = db.plugins:cache_key(plugin)

      helpers.wait_until(function()
        res = assert(admin_client:send {
          method = "GET",
          path   = "/cache/" .. cache_key
        })
        res:read_body()
        return res.status ~= 200
      end)

      local res = assert(proxy_client:send {
        method  = "GET",
        path    = "/request",
        headers = {
          ["Host"] = "ip-restriction2.com",
          ["X-Real-IP"] = "::1",
        }
      })
      local body = assert.res_status(403, res)
      local json = cjson.decode(body)
      assert.same({ message = "Your IP address is not allowed" }, json)
    end)

    describe("#regression", function()
      it("handles a CIDR entry with ::/0", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/status/200",
          headers = {
            ["Host"] = "ip-restriction6.com",
            ["X-Real-IP"] = "::1",
          }
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.equal("::1", json.vars.remote_addr)
      end)
    end)
  end)

  describe("Plugin: ip-restriction (access) [#" .. strategy .. "]", function()
    local proxy_client
    local admin_client

    lazy_setup(function()
      local bp
      bp = helpers.get_db_utils(strategy, {
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

      bp.plugins:insert {
        name     = "ip-restriction",
        route = { id = route1.id },
        config   = {
          deny = { "::4" }
        },
      }

      bp.plugins:insert {
        name     = "ip-restriction",
        route = { id = route2.id },
        config   = {
          allow = { "::4" }
        },
      }

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

    describe("deny", function()
      it("allows with allowed X-Forwarded-For header", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          headers = {
            ["Host"]            = "ip-restriction1.com",
            ["X-Forwarded-For"] = "::3",
          }
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.equal("::3", json.vars.remote_addr)
      end)
      it("blocks with not allowed X-Forwarded-For header", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/status/200",
          headers = {
            ["Host"]            = "ip-restriction1.com",
            ["X-Forwarded-For"] = "::4"
          }
        })
        local body = assert.res_status(403, res)
        local json = cjson.decode(body)
        assert.same({ message = "Your IP address is not allowed" }, json)
      end)
      it("blocks with blocked complex X-Forwarded-For header", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/status/200",
          headers = {
            ["Host"]            = "ip-restriction1.com",
            ["X-Forwarded-For"] = "::4, ::3"
          }
        })
        local body = assert.res_status(403, res)
        local json = cjson.decode(body)
        assert.same({ message = "Your IP address is not allowed" }, json)
      end)
      it("allows with allowed complex X-Forwarded-For header", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/status/200",
          headers = {
            ["Host"]            = "ip-restriction1.com",
            ["X-Forwarded-For"] = "::3, ::4"
          }
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.equal("::3", json.vars.remote_addr)
      end)
    end)

    describe("allow", function()
      it("block with not allowed X-Forwarded-For header", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/status/200",
          headers = {
            ["Host"]            = "ip-restriction2.com",
            ["X-Forwarded-For"] = "::3"
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
            ["Host"]            = "ip-restriction2.com",
            ["X-Forwarded-For"] = "::4"
          }
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.equal("::4", json.vars.remote_addr)
      end)
      it("allows with allowed complex X-Forwarded-For header", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/status/200",
          headers = {
            ["Host"]            = "ip-restriction2.com",
            ["X-Forwarded-For"] = "::4, ::3"
          }
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.equal("::4", json.vars.remote_addr)
      end)
      it("blocks with blocked complex X-Forwarded-For header", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/status/200",
          headers = {
            ["Host"]            = "ip-restriction2.com",
            ["X-Forwarded-For"] = "::3, ::4"
          }
        })
        local body = assert.res_status(403, res)
        local json = cjson.decode(body)
        assert.same({ message = "Your IP address is not allowed" }, json)
      end)
    end)
  end)
end
