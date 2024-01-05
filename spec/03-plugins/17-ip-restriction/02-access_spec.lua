local helpers = require "spec.helpers"
local cjson   = require "cjson"

local MESSAGE = "echo, ping, pong. echo, ping, pong. echo, ping, pong.\n"

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
        hosts = { "ip-restriction1.test" },
      }

      local route2 = bp.routes:insert {
        hosts = { "ip-restriction2.test" },
      }

      local route3 = bp.routes:insert {
        hosts = { "ip-restriction3.test" },
      }

      local route4 = bp.routes:insert {
        hosts = { "ip-restriction4.test" },
      }

      local route5 = bp.routes:insert {
        hosts = { "ip-restriction5.test" },
      }

      local route6 = bp.routes:insert {
        hosts = { "ip-restriction6.test" },
      }

      local route7 = bp.routes:insert {
        hosts = { "ip-restriction7.test" },
      }

      local route8 = bp.routes:insert {
        hosts = { "ip-restriction8.test" },
      }

      local route9 = bp.routes:insert {
        hosts = { "ip-restriction9.test" },
      }

      local route10 = bp.routes:insert {
        hosts = { "ip-restriction10.test" },
      }

      local route11 = bp.routes:insert {
        hosts = { "ip-restriction11.test" },
      }

      local route12 = bp.routes:insert {
        hosts = { "ip-restriction12.test" },
      }

      local grpc_service = bp.services:insert {
          name = "grpc1",
          url = helpers.grpcbin_url,
      }

      local route_grpc_deny = assert(bp.routes:insert {
        protocols = { "grpc" },
        paths = { "/hello.HelloService/" },
        hosts = { "ip-restriction-grpc1.test" },
        service = grpc_service,
      })

      local route_grpc_allow = assert(bp.routes:insert {
        protocols = { "grpc" },
        paths = { "/hello.HelloService/" },
        hosts = { "ip-restriction-grpc2.test" },
        service = grpc_service,
      })

      local route_grpc_xforwarded_deny = assert(bp.routes:insert {
        protocols = { "grpc" },
        paths = { "/hello.HelloService/" },
        hosts = { "ip-restriction-grpc3.test" },
        service = grpc_service,
      })

      -- tcp services/routes
      local tcp_srv = bp.services:insert({
        name = "tcp",
        host = helpers.mock_upstream_host,
        port = helpers.mock_upstream_stream_port,
        protocol = "tcp"
      })

      local tls_srv = bp.services:insert({
        name = "tls",
        host = helpers.mock_upstream_host,
        port = helpers.mock_upstream_stream_ssl_port,
        protocol = "tls"
      })

      local route_tcp_allow = bp.routes:insert {
        destinations = {
          {
            port = 19000,
          },
        },
        protocols = {
          "tcp",
        },
        service = tcp_srv,
      }

      local route_tcp_deny = bp.routes:insert {
        destinations = {
          {
            port = 19443,
          },
        },
        protocols = {
          "tls",
        },
        service = tls_srv,
      }

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

      bp.plugins:insert {
        name     = "ip-restriction",
        route = { id = route12.id },
        config   = {
          deny = { "127.0.0.0/24" },
          status = 401,
          message = "Forbidden"
        },
      }

      assert(db.plugins:insert {
        name     = "ip-restriction",
        route = { id = route_tcp_allow.id },
        config   = {
          allow = { "127.0.0.0/24" },
        },
      })

      assert(db.plugins:insert {
        name     = "ip-restriction",
        route = { id = route_tcp_deny.id },
        config   = {
          deny = { "127.0.0.0/24" },
        },
      })

      assert(db.plugins:insert {
        name     = "ip-restriction",
        route = { id = route_grpc_deny.id },
        config   = {
          deny = { "127.0.0.0/24" },
        },
      })

      assert(db.plugins:insert {
        name     = "ip-restriction",
        route = { id = route_grpc_allow.id },
        config   = {
          deny = { "127.0.0.2/32" }
        },
      })

      assert(db.plugins:insert {
        name     = "ip-restriction",
        route = { id = route_grpc_xforwarded_deny.id },
        config   = {
          allow = { "127.0.0.4/32" },
        },
      })

      assert(helpers.start_kong {
        database          = strategy,
        real_ip_header    = "X-Forwarded-For",
        real_ip_recursive = "on",
        trusted_ips       = "0.0.0.0/0, ::/0",
        nginx_conf        = "spec/fixtures/custom_nginx.template",
        stream_listen     = helpers.get_proxy_ip(false) .. ":19000," ..
                            helpers.get_proxy_ip(false) .. ":19443 ssl"
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
            ["Host"] = "ip-restriction1.test"
          }
        })
        local body = assert.res_status(403, res)
        assert.matches("IP address not allowed", body)
      end)

      it("blocks a request when the IP is denied with status/message", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/status/200",
          headers = {
            ["Host"] = "ip-restriction12.test"
          }
        })
        local body = assert.res_status(401, res)
        local json = cjson.decode(body)

        assert.not_nil(json)
        assert.matches("Forbidden", json.message)
      end)

      it("blocks a request when the IP is denied #grpc", function()
        local ok, err =   helpers.proxy_client_grpc(){
          service = "hello.HelloService.SayHello",
          opts = {
            ["-authority"] = "ip-restriction-grpc1.test",
            ["-v"] = true,
          },
        }
        assert.falsy(ok)
        assert.matches("Code: PermissionDenied", err)
      end)

      it("blocks a request when the IP is denied #tcp", function()
        local tcp = ngx.socket.tcp()
        assert(tcp:connect(helpers.get_proxy_ip(true), 19443))
        assert(tcp:sslhandshake(nil, nil, false))
        assert(tcp:send(MESSAGE))
        assert(tcp:receive("*a"))
        tcp:close()

        assert.logfile().has.line("IP address not allowed", true)
      end)

      it("allows a request when the IP is not denied", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          headers = {
            ["Host"] = "ip-restriction2.test"
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
            ["-authority"] = "ip-restriction-grpc2.test",
            ["-v"] = true,
          },
        }
        assert.truthy(ok)
      end)

      it("allows a request when the IP is not denied #tcp", function()
        local tcp = ngx.socket.tcp()
        local ip = helpers.get_proxy_ip(false)
        assert(tcp:connect(ip, 19000))
        assert(tcp:send(MESSAGE))
        local body = assert(tcp:receive("*a"))
        assert.equal(MESSAGE, body)
        tcp:close()
      end)

      it("blocks IP with CIDR", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/status/200",
          headers = {
            ["Host"] = "ip-restriction5.test"
          }
        })
        local body = assert.res_status(403, res)
        assert.matches("IP address not allowed", body)
      end)
      it("blocks an IP on a allowed CIDR range", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/status/200",
          headers = {
            ["Host"] = "ip-restriction10.test"
          }
        })
        local body = assert.res_status(403, res)
        assert.matches("IP address not allowed", body)
      end)
      it("takes precedence over an allowed IP", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/status/200",
          headers = {
            ["Host"] = "ip-restriction9.test"
          }
        })
        local body = assert.res_status(403, res)
        assert.matches("IP address not allowed", body)
      end)
      it("takes precedence over an allowed CIDR range", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/status/200",
          headers = {
            ["Host"] = "ip-restriction11.test"
          }
        })
        local body = assert.res_status(403, res)
        assert.matches("IP address not allowed", body)
      end)

      describe("X-Forwarded-For", function()
        it("allows without any X-Forwarded-For and allowed IP", function()
          local res = assert(proxy_client:send {
            method  = "GET",
            path    = "/request",
            headers = {
              ["Host"] = "ip-restriction7.test"
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
              ["Host"]            = "ip-restriction7.test",
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
              ["Host"]            = "ip-restriction7.test",
              ["X-Forwarded-For"] = "127.0.0.4"
            }
          })
          local body = assert.res_status(403, res)
          assert.matches("IP address not allowed", body)
        end)
      end)
    end)

    describe("allow", function()
      it("blocks a request when the IP is not allowed", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/status/200",
          headers = {
            ["Host"] = "ip-restriction3.test"
          }
        })
        local body = assert.res_status(403, res)
        assert.matches("IP address not allowed", body)
      end)
      it("allows a allowed IP", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/status/200",
          headers = {
            ["Host"] = "ip-restriction4.test"
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
              ["Host"] = "ip-restriction6.test"
            }
          })
          local body = assert.res_status(403, res)
          assert.matches("IP address not allowed", body)
        end)
        it("block with not allowed X-Forwarded-For header", function()
          local res = assert(proxy_client:send {
            method  = "GET",
            path    = "/status/200",
            headers = {
              ["Host"]            = "ip-restriction6.test",
              ["X-Forwarded-For"] = "127.0.0.3"
            }
          })
          local body = assert.res_status(403, res)
          assert.matches("IP address not allowed", body)
        end)
        it("block with not allowed X-Forwarded-For header #grpc", function()
          local ok, err = helpers.proxy_client_grpc(){
            service = "hello.HelloService.SayHello",
            opts = {
              ["-authority"] = "ip-restriction-grpc3.test",
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
              ["Host"]            = "ip-restriction6.test",
              ["X-Forwarded-For"] = "127.0.0.4"
            }
          })
          assert.res_status(200, res)
        end)
        it("allows with allowed X-Forwarded-For header #grpc", function()
          assert.truthy(helpers.proxy_client_grpc(){
            service = "hello.HelloService.SayHello",
            opts = {
              ["-authority"] = "ip-restriction-grpc3.test",
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
              ["Host"]            = "ip-restriction6.test",
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
          ["Host"] = "ip-restriction2.test"
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

      helpers.pwait_until(function()
        res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          headers = {
            ["Host"] = "ip-restriction2.test"
          }
        })
        local body = assert.res_status(403, res)
        assert.matches("IP address not allowed", body)
      end)

      res = assert(admin_client:send {
        method  = "PATCH",
        path    = "/plugins/" .. plugin.id,
        body    = {
          config = { deny = { "127.0.0.2", "127.0.0.3" } },
        },
        headers = {
          ["Content-Type"] = "application/json"
        }
      })
      assert.res_status(200, res)

      helpers.pwait_until(function()
        res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          headers = {
            ["Host"] = "ip-restriction2.test"
          }
        })
        assert.res_status(200, res)
      end)
    end)

    describe("#regression", function()
      it("handles a CIDR entry with 0.0.0.0/0", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/status/200",
          headers = {
            ["Host"] = "ip-restriction8.test"
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
        hosts = { "ip-restriction1.test" },
      }

      local route2 = bp.routes:insert {
        hosts = { "ip-restriction2.test" },
      }

      local route3 = bp.routes:insert {
        hosts = { "ip-restriction3.test" },
      }

      local route4 = bp.routes:insert {
        hosts = { "ip-restriction4.test" },
      }

      local route5 = bp.routes:insert {
        hosts = { "ip-restriction5.test" },
      }

      local route6 = bp.routes:insert {
        hosts = { "ip-restriction6.test" },
      }

      local route7 = bp.routes:insert {
        hosts = { "ip-restriction7.test" },
      }

      local route8 = bp.routes:insert {
        hosts = { "ip-restriction8.test" },
      }

      local route9 = bp.routes:insert {
        hosts = { "ip-restriction9.test" },
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
            ["Host"] = "ip-restriction1.test",
            ["X-Real-IP"] = "::1",
          }
        })
        local body = assert.res_status(403, res)
        assert.matches("IP address not allowed", body)
      end)
      it("allows a request when the IPv6 is not denied", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          headers = {
            ["Host"] = "ip-restriction2.test",
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
            ["Host"] = "ip-restriction3.test",
            ["X-Real-IP"] = "fe80::1",
          }
        })
        local body = assert.res_status(403, res)
        assert.matches("IP address not allowed", body)
      end)
      it("blocks an IPv6 on a allowed IPv6 CIDR range", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/status/200",
          headers = {
            ["Host"] = "ip-restriction8.test",
            ["X-Real-IP"] = "::1",
          }
        })
        local body = assert.res_status(403, res)
        assert.matches("IP address not allowed", body)
      end)
      it("takes precedence over an allowed IPv6", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/status/200",
          headers = {
            ["Host"] = "ip-restriction7.test",
            ["X-Real-IP"] = "::1",
          }
        })
        local body = assert.res_status(403, res)
        assert.matches("IP address not allowed", body)
      end)
      it("takes precedence over an allowed IPv6 CIDR range", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/status/200",
          headers = {
            ["Host"] = "ip-restriction9.test"
          }
        })
        local body = assert.res_status(403, res)
        assert.matches("IP address not allowed", body)
      end)
    end)

    describe("allow", function()
      it("blocks a request when the IPv6 is not allowed", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/status/200",
          headers = {
            ["Host"] = "ip-restriction4.test",
            ["X-Real-IP"] = "::1",
          }
        })
        local body = assert.res_status(403, res)
        assert.matches("IP address not allowed", body)
      end)
      it("allows a allowed IPv6", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/status/200",
          headers = {
            ["Host"] = "ip-restriction5.test",
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
          ["Host"] = "ip-restriction2.test",
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
          ["Host"] = "ip-restriction2.test",
          ["X-Real-IP"] = "::1",
        }
      })
      local body = assert.res_status(403, res)
      assert.matches("IP address not allowed", body)

      res = assert(admin_client:send {
        method  = "PATCH",
        path    = "/plugins/" .. plugin.id,
        body    = {
          config = { deny = { "::2", "::3" } },
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
          ["Host"] = "ip-restriction2.test",
          ["X-Real-IP"] = "::1",
        }
      })
      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      assert.equal("::1", json.vars.remote_addr)
    end)

    describe("#regression", function()
      it("handles a CIDR entry with ::/0", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/status/200",
          headers = {
            ["Host"] = "ip-restriction6.test",
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
        hosts = { "ip-restriction1.test" },
      }

      local route2 = bp.routes:insert {
        hosts = { "ip-restriction2.test" },
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
            ["Host"]            = "ip-restriction1.test",
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
            ["Host"]            = "ip-restriction1.test",
            ["X-Forwarded-For"] = "::4"
          }
        })
        local body = assert.res_status(403, res)
        assert.matches("IP address not allowed", body)
      end)
      it("blocks with blocked complex X-Forwarded-For header", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/status/200",
          headers = {
            ["Host"]            = "ip-restriction1.test",
            ["X-Forwarded-For"] = "::4, ::3"
          }
        })
        local body = assert.res_status(403, res)
        assert.matches("IP address not allowed", body)
      end)
      it("allows with allowed complex X-Forwarded-For header", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/status/200",
          headers = {
            ["Host"]            = "ip-restriction1.test",
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
            ["Host"]            = "ip-restriction2.test",
            ["X-Forwarded-For"] = "::3"
          }
        })
        local body = assert.res_status(403, res)
        assert.matches("IP address not allowed", body)
      end)
      it("allows with allowed X-Forwarded-For header", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/status/200",
          headers = {
            ["Host"]            = "ip-restriction2.test",
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
            ["Host"]            = "ip-restriction2.test",
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
            ["Host"]            = "ip-restriction2.test",
            ["X-Forwarded-For"] = "::3, ::4"
          }
        })
        local body = assert.res_status(403, res)
        assert.matches("IP address not allowed", body)
      end)
    end)
  end)
end
