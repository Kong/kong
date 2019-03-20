local helpers = require "spec.helpers"
local cjson   = require "cjson"


for _, strategy in helpers.each_strategy() do
  describe("Plugin: ACL (access) [#" .. strategy .. "]", function()
    local proxy_client
    local admin_client
    local bp
    local db

    lazy_setup(function()
      bp, db = helpers.get_db_utils(strategy, {
        "routes",
        "services",
        "plugins",
        "kongsumers",
        "acls",
        "keyauth_credentials",
      })

      local kongsumer1 = bp.kongsumers:insert {
        username = "kongsumer1"
      }

      bp.keyauth_credentials:insert {
        key      = "apikey123",
        kongsumer = { id = kongsumer1.id },
      }

      local kongsumer2 = bp.kongsumers:insert {
        username = "kongsumer2"
      }

      bp.keyauth_credentials:insert {
        key      = "apikey124",
        kongsumer = { id = kongsumer2.id },
      }

      bp.acls:insert {
        group    = "admin",
        kongsumer = { id = kongsumer2.id },
      }

      local kongsumer3 = bp.kongsumers:insert {
        username = "kongsumer3"
      }

      bp.keyauth_credentials:insert {
        key      = "apikey125",
        kongsumer = { id = kongsumer3.id },
      }

      bp.acls:insert {
        group    = "pro",
        kongsumer = { id = kongsumer3.id },
      }

      bp.acls:insert {
        group       = "hello",
        kongsumer = { id = kongsumer3.id },
      }

      local kongsumer4 = bp.kongsumers:insert {
        username = "kongsumer4"
      }

      bp.keyauth_credentials:insert {
        key      = "apikey126",
        kongsumer = { id = kongsumer4.id },
      }

      bp.acls:insert {
        group    = "free",
        kongsumer = { id = kongsumer4.id },
      }

      bp.acls:insert {
        group    = "hello",
        kongsumer = { id = kongsumer4.id },
      }

      local anonymous = bp.kongsumers:insert {
        username = "anonymous"
      }

      bp.acls:insert {
        group    = "anonymous",
        kongsumer = { id = anonymous.id },
      }

      local route1 = bp.routes:insert {
        hosts = { "acl1.com" },
      }

      bp.plugins:insert {
        name     = "acl",
        route = { id = route1.id },
        config   = {
          whitelist = { "admin" },
        }
      }

      local route2 = bp.routes:insert {
        hosts = { "acl2.com" },
      }

      bp.plugins:insert {
        name     = "acl",
        route = { id = route2.id },
        config   = {
          whitelist = { "admin" },
        }
      }

      bp.plugins:insert {
        name     = "key-auth",
        route = { id = route2.id },
        config   = {}
      }

      local route3 = bp.routes:insert {
        hosts = { "acl3.com" },
      }

      bp.plugins:insert {
        name     = "acl",
        route = { id = route3.id },
        config   = {
          blacklist = {"admin"}
        }
      }

      bp.plugins:insert {
        name     = "key-auth",
        route = { id = route3.id },
        config   = {}
      }

      local route4 = bp.routes:insert {
        hosts = { "acl4.com" },
      }

      bp.plugins:insert {
        name     = "acl",
        route = { id = route4.id },
        config   = {
          whitelist = {"admin", "pro"}
        }
      }

      bp.plugins:insert {
        name     = "key-auth",
        route = { id = route4.id },
        config   = {}
      }

      local route5 = bp.routes:insert {
        hosts = { "acl5.com" },
      }

      bp.plugins:insert {
        name     = "acl",
        route = { id = route5.id },
        config   = {
          blacklist = {"admin", "pro"}
        }
      }

      bp.plugins:insert {
        name     = "key-auth",
        route = { id = route5.id },
        config   = {}
      }

      local route6 = bp.routes:insert {
        hosts = { "acl6.com" },
      }

      bp.plugins:insert {
        name     = "acl",
        route = { id = route6.id },
        config   = {
          blacklist = {"admin", "pro", "hello"}
        }
      }

      bp.plugins:insert {
        name     = "key-auth",
        route = { id = route6.id },
        config   = {}
      }

      local route7 = bp.routes:insert {
        hosts = { "acl7.com" },
      }

      bp.plugins:insert {
        name     = "acl",
        route = { id = route7.id },
        config   = {
          whitelist = {"admin", "pro", "hello"}
        }
      }
      bp.plugins:insert {
        name     = "key-auth",
        route = { id = route7.id },
        config   = {}
      }

      local route8 = bp.routes:insert {
        hosts = { "acl8.com" },
      }

      bp.plugins:insert {
        name     = "acl",
        route = { id = route8.id },
        config   = {
          whitelist = {"anonymous"}
        }
      }

      bp.plugins:insert {
        name     = "key-auth",
        route = { id = route8.id },
        config   = {
          anonymous = anonymous.id,
        }
      }

      local route9 = bp.routes:insert {
        hosts = { "acl9.com" },
      }

      bp.plugins:insert {
        name = "acl",
        route = { id = route9.id },
        config = {
          whitelist = { "admin" },
          hide_groups_header = true
        }
      }

      bp.plugins:insert {
        name = "key-auth",
        route = { id = route9.id },
        config = {}
      }

      local route10 = bp.routes:insert {
        hosts = { "acl10.com" },
      }

      bp.plugins:insert {
        name = "acl",
        route = { id = route10.id },
        config = {
          whitelist = { "admin" },
          hide_groups_header = false
        }
      }

      bp.plugins:insert {
        name = "key-auth",
        route = { id = route10.id },
        config = {}
      }

      assert(helpers.start_kong({
        database   = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }))
    end)

    before_each(function()
      proxy_client = helpers.proxy_client()
      admin_client = helpers.admin_client()
    end)

    after_each(function ()
      proxy_client:close()
      admin_client:close()
    end)

    lazy_teardown(function()
      helpers.stop_kong()
    end)


    describe("Mapping to kongsumer", function()
      it("should work with kongsumer with credentials", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request?apikey=apikey124",
          headers = {
            ["Host"] = "acl2.com"
          }
        })

        local body = cjson.decode(assert.res_status(200, res))
        assert.equal("admin", body.headers["x-kongsumer-groups"])
      end)

      it("should work with kongsumer without credentials", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          headers = {
            ["Host"] = "acl8.com"
          }
        })

        local body = cjson.decode(assert.res_status(200, res))
        assert.equal("anonymous", body.headers["x-kongsumer-groups"])
      end)
    end)

    describe("Simple lists", function()
      it("should fail when an authentication plugin is missing", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/status/200",
          headers = {
            ["Host"] = "acl1.com"
          }
        })
        local body = assert.res_status(403, res)
        local json = cjson.decode(body)
        assert.same({ message = "You cannot consume this service" }, json)
      end)

      it("should fail when not in whitelist", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/status/200?apikey=apikey123",
          headers = {
            ["Host"] = "acl2.com"
          }
        })
        local body = assert.res_status(403, res)
        local json = cjson.decode(body)
        assert.same({ message = "You cannot consume this service" }, json)
      end)

      it("should work when in whitelist", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request?apikey=apikey124",
          headers = {
            ["Host"] = "acl2.com"
          }
        })
        local body = cjson.decode(assert.res_status(200, res))
        assert.equal("admin", body.headers["x-kongsumer-groups"])
      end)

      it("should not send x-kongsumer-groups header when hide_groups_header flag true", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request?apikey=apikey124",
          headers = {
            ["Host"] = "acl9.com"
          }
        })
        local body = cjson.decode(assert.res_status(200, res))
        assert.equal(nil, body.headers["x-kongsumer-groups"])
      end)

      it("should send x-kongsumer-groups header when hide_groups_header flag false", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request?apikey=apikey124",
          headers = {
            ["Host"] = "acl10.com"
          }
        })
        local body = cjson.decode(assert.res_status(200, res))
        assert.equal("admin", body.headers["x-kongsumer-groups"])
      end)

      it("should work when not in blacklist", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request?apikey=apikey123",
          headers = {
            ["Host"] = "acl3.com"
          }
        })
        assert.res_status(200, res)
      end)

      it("should fail when in blacklist", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request?apikey=apikey124",
          headers = {
            ["Host"] = "acl3.com"
          }
        })
        local body = assert.res_status(403, res)
        local json = cjson.decode(body)
        assert.same({ message = "You cannot consume this service" }, json)
      end)
    end)

    describe("Multi lists", function()
      it("should work when in whitelist", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request?apikey=apikey125",
          headers = {
            ["Host"] = "acl4.com"
          }
        })
        local body = cjson.decode(assert.res_status(200, res))
        assert.True(body.headers["x-kongsumer-groups"] == "pro, hello" or body.headers["x-kongsumer-groups"] == "hello, pro")
      end)

      it("should fail when not in whitelist", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request?apikey=apikey126",
          headers = {
            ["Host"] = "acl4.com"
          }
        })
        local body = assert.res_status(403, res)
        local json = cjson.decode(body)
        assert.same({ message = "You cannot consume this service" }, json)
      end)

      it("should fail when in blacklist", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request?apikey=apikey125",
          headers = {
            ["Host"] = "acl5.com"
          }
        })
        local body = assert.res_status(403, res)
        local json = cjson.decode(body)
        assert.same({ message = "You cannot consume this service" }, json)
      end)

      it("should work when not in blacklist", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request?apikey=apikey126",
          headers = {
            ["Host"] = "acl5.com"
          }
        })
        assert.res_status(200, res)
      end)

      it("should not work when one of the ACLs in the blacklist", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request?apikey=apikey126",
          headers = {
            ["Host"] = "acl6.com"
          }
        })
        local body = assert.res_status(403, res)
        local json = cjson.decode(body)
        assert.same({ message = "You cannot consume this service" }, json)
      end)

      it("should work when one of the ACLs in the whitelist", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request?apikey=apikey126",
          headers = {
            ["Host"] = "acl7.com"
          }
        })
        assert.res_status(200, res)
      end)

      it("should not work when at least one of the ACLs in the blacklist", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request?apikey=apikey125",
          headers = {
            ["Host"] = "acl6.com"
          }
        })
        local body = assert.res_status(403, res)
        local json = cjson.decode(body)
        assert.same({ message = "You cannot consume this service" }, json)
      end)
    end)

    describe("Real-world usage", function()
      it("should not fail when multiple rules are set fast", function()
        -- Create kongsumer
        local res = assert(admin_client:send {
          method  = "POST",
          path    = "/kongsumers/",
          headers = {
            ["Content-Type"] = "application/json"
          },
          body    = {
            username = "acl_kongsumer"
          }
        })
        local body = cjson.decode(assert.res_status(201, res))
        local kongsumer = { id = body.id }

        -- Create key
        local res = assert(admin_client:send {
          method  = "POST",
          path    = "/kongsumers/acl_kongsumer/key-auth/",
          headers = {
            ["Content-Type"] = "application/json"
          },
          body    = {
            key              = "secret123"
          }
        })
        assert.res_status(201, res)

        for i = 1, 3 do
          -- Create API
          local service = bp.services:insert()

          local res = assert(admin_client:send {
            method  = "POST",
            path    = "/routes/",
            headers = {
              ["Content-Type"] = "application/json"
            },
            body    = {
              hosts            = { "acl_test" .. i .. ".com" },
              protocols        = { "http", "https" },
              service          = {
                id = service.id
              },
            },
          })

          local body = assert.res_status(201, res)
          local json = cjson.decode(body)

          -- Add the ACL plugin to the new API with the new group
          local res = assert(admin_client:send {
            method  = "POST",
            path    = "/plugins",
            headers = {
              ["Content-Type"]     = "application/json"
            },
            body    = {
              name                 = "acl",
              config = { whitelist = { "admin" .. i } },
              route = { id = json.id },
            }
          })

          assert.res_status(201, res)

          -- Add key-authentication to API
          local res = assert(admin_client:send {
            method  = "POST",
            path    = "/plugins",
            headers = {
              ["Content-Type"] = "application/json"
            },
            body    = {
              name     = "key-auth",
              route = { id = json.id },
            }
          })
          assert.res_status(201, res)

          -- Add a new group to the kongsumer
          local res = assert(admin_client:send {
            method  = "POST",
            path    = "/kongsumers/acl_kongsumer/acls/",
            headers = {
              ["Content-Type"] = "application/json"
            },
            body    = {
              group            = "admin" .. i
            }
          })
          assert.res_status(201, res)

          -- Wait for cache to be invalidated
          local cache_key = db.acls:cache_key(kongsumer)

          helpers.wait_until(function()
            local res = assert(admin_client:send {
              method  = "GET",
              path    = "/cache/" .. cache_key
            })
            res:read_body()
            return res.status == 404
          end, 5)

          -- Make the request, and it should work

          local res
          helpers.wait_until(function()
            res = assert(proxy_client:send {
              method  = "GET",
              path    = "/status/200?apikey=secret123",
              headers = {
                ["Host"] = "acl_test" .. i .. ".com"
              }
            })
            res:read_body()
            return res.status ~= 404
          end, 5)

          assert.res_status(200, res)
        end
      end)
    end)
  end)
end
