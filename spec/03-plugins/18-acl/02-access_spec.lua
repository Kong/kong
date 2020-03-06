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
        "consumers",
        "acls",
        "keyauth_credentials",
      }, { "ctx-checker" })

      local consumer1 = bp.consumers:insert {
        username = "consumer1"
      }

      bp.keyauth_credentials:insert {
        key      = "apikey123",
        consumer = { id = consumer1.id },
      }

      local consumer2 = bp.consumers:insert {
        username = "consumer2"
      }

      bp.keyauth_credentials:insert {
        key      = "apikey124",
        consumer = { id = consumer2.id },
      }

      bp.acls:insert {
        group    = "admin",
        consumer = { id = consumer2.id },
      }

      local consumer3 = bp.consumers:insert {
        username = "consumer3"
      }

      bp.keyauth_credentials:insert {
        key      = "apikey125",
        consumer = { id = consumer3.id },
      }

      bp.acls:insert {
        group    = "pro",
        consumer = { id = consumer3.id },
      }

      bp.acls:insert {
        group       = "hello",
        consumer = { id = consumer3.id },
      }

      local consumer4 = bp.consumers:insert {
        username = "consumer4"
      }

      bp.keyauth_credentials:insert {
        key      = "apikey126",
        consumer = { id = consumer4.id },
      }

      bp.acls:insert {
        group    = "free",
        consumer = { id = consumer4.id },
      }

      bp.acls:insert {
        group    = "hello",
        consumer = { id = consumer4.id },
      }

      local anonymous = bp.consumers:insert {
        username = "anonymous"
      }

      bp.acls:insert {
        group    = "anonymous",
        consumer = { id = anonymous.id },
      }

      local route1 = bp.routes:insert {
        hosts = { "acl1.com" },
      }

      bp.plugins:insert {
        name = "acl",
        route = { id = route1.id },
        config = {
          whitelist = { "admin" },
        }
      }

      local route2 = bp.routes:insert {
        hosts = { "acl2.com" },
      }

      bp.plugins:insert {
        name = "acl",
        route = { id = route2.id },
        config = {
          whitelist = { "admin" },
        }
      }

      bp.plugins:insert {
        name = "key-auth",
        route = { id = route2.id },
        config = {}
      }

      local route2b = bp.routes:insert {
        hosts = { "acl2b.com" },
      }

      bp.plugins:insert {
        name = "acl",
        route = { id = route2b.id },
        config = {
          whitelist = { "admin" },
        }
      }

      bp.plugins:insert {
        name = "ctx-checker",
        route = { id = route2b.id },
        config = {
          ctx_kind      = "kong.ctx.shared",
          ctx_set_field = "authenticated_groups",
          ctx_set_array = { "admin" },
        }
      }

      local route2c = bp.routes:insert {
        hosts = { "acl2c.com" },
      }

      bp.plugins:insert {
        name = "acl",
        route = { id = route2c.id },
        config = {
          whitelist = { "admin" },
        }
      }

      bp.plugins:insert {
        name = "ctx-checker",
        route = { id = route2c.id },
        config = {
          ctx_kind      = "kong.ctx.shared",
          ctx_set_field = "authenticated_groups",
          ctx_set_array = { },
        }
      }

      local route3 = bp.routes:insert {
        hosts = { "acl3.com" },
      }

      bp.plugins:insert {
        name = "acl",
        route = { id = route3.id },
        config = {
          blacklist = { "admin" }
        }
      }

      bp.plugins:insert {
        name = "key-auth",
        route = { id = route3.id },
        config = {}
      }

      local route3b = bp.routes:insert {
        hosts = { "acl3b.com" },
      }

      bp.plugins:insert {
        name = "acl",
        route = { id = route3b.id },
        config = {
          blacklist = { "admin" }
        }
      }

      bp.plugins:insert {
        name = "ctx-checker",
        route = { id = route3b.id },
        config = {
          ctx_kind      = "kong.ctx.shared",
          ctx_set_field = "authenticated_groups",
          ctx_set_array = { },
        }
      }

      local route3c = bp.routes:insert {
        hosts = { "acl3c.com" },
      }

      bp.plugins:insert {
        name = "acl",
        route = { id = route3c.id },
        config = {
          blacklist = { "admin" }
        }
      }

      bp.plugins:insert {
        name = "ctx-checker",
        route = { id = route3c.id },
        config = {
          ctx_kind      = "kong.ctx.shared",
          ctx_set_field = "authenticated_groups",
          ctx_set_array = { "admin" },
        }
      }

      local route4 = bp.routes:insert {
        hosts = { "acl4.com" },
      }

      bp.plugins:insert {
        name = "acl",
        route = { id = route4.id },
        config = {
          whitelist = { "admin", "pro" }
        }
      }

      bp.plugins:insert {
        name = "key-auth",
        route = { id = route4.id },
        config = {}
      }

      local route4b = bp.routes:insert {
        hosts = { "acl4b.com" },
      }

      bp.plugins:insert {
        name = "acl",
        route = { id = route4b.id },
        config = {
          whitelist = { "admin", "pro" }
        }
      }

      bp.plugins:insert {
        name = "ctx-checker",
        route = { id = route4b.id },
        config = {
          ctx_kind      = "kong.ctx.shared",
          ctx_set_field = "authenticated_groups",
          ctx_set_array = { "pro", "hello" },
        }
      }

      local route4c = bp.routes:insert {
        hosts = { "acl4c.com" },
      }

      bp.plugins:insert {
        name = "acl",
        route = { id = route4c.id },
        config = {
          whitelist = { "admin", "pro" }
        }
      }

      bp.plugins:insert {
        name = "ctx-checker",
        route = { id = route4c.id },
        config = {
          ctx_kind      = "kong.ctx.shared",
          ctx_set_field = "authenticated_groups",
          ctx_set_array = { "free", "hello" },
        }
      }

      local route5 = bp.routes:insert {
        hosts = { "acl5.com" },
      }

      bp.plugins:insert {
        name = "acl",
        route = { id = route5.id },
        config = {
          blacklist = { "admin", "pro" }
        }
      }

      bp.plugins:insert {
        name = "key-auth",
        route = { id = route5.id },
        config = {}
      }

      local route5b = bp.routes:insert {
        hosts = { "acl5b.com" },
      }

      bp.plugins:insert {
        name = "acl",
        route = { id = route5b.id },
        config = {
          blacklist = { "admin", "pro" }
        }
      }

      bp.plugins:insert {
        name = "ctx-checker",
        route = { id = route5b.id },
        config = {
          ctx_kind      = "kong.ctx.shared",
          ctx_set_field = "authenticated_groups",
          ctx_set_array = { "pro", "hello" },
        }
      }

      local route5c = bp.routes:insert {
        hosts = { "acl5c.com" },
      }

      bp.plugins:insert {
        name = "acl",
        route = { id = route5c.id },
        config = {
          blacklist = { "admin", "pro" }
        }
      }

      bp.plugins:insert {
        name = "ctx-checker",
        route = { id = route5c.id },
        config = {
          ctx_kind      = "kong.ctx.shared",
          ctx_set_field = "authenticated_groups",
          ctx_set_array = { "free", "hello" },
        }
      }

      local route6 = bp.routes:insert {
        hosts = { "acl6.com" },
      }

      bp.plugins:insert {
        name = "acl",
        route = { id = route6.id },
        config = {
          blacklist = { "admin", "pro", "hello" }
        }
      }

      bp.plugins:insert {
        name = "key-auth",
        route = { id = route6.id },
        config = {}
      }

      local route6b = bp.routes:insert {
        hosts = { "acl6b.com" },
      }

      bp.plugins:insert {
        name = "acl",
        route = { id = route6b.id },
        config = {
          blacklist = { "admin", "pro", "hello" }
        }
      }

      bp.plugins:insert {
        name = "ctx-checker",
        route = { id = route6b.id },
        config = {
          ctx_kind      = "kong.ctx.shared",
          ctx_set_field = "authenticated_groups",
          ctx_set_array = { "free", "hello" },
        }
      }

      local route6c = bp.routes:insert {
        hosts = { "acl6c.com" },
      }

      bp.plugins:insert {
        name = "acl",
        route = { id = route6c.id },
        config = {
          blacklist = { "admin", "pro", "hello" }
        }
      }

      bp.plugins:insert {
        name = "ctx-checker",
        route = { id = route6c.id },
        config = {
          ctx_kind      = "kong.ctx.shared",
          ctx_set_field = "authenticated_groups",
          ctx_set_array = { "pro", "hello" },
        }
      }

      local route7 = bp.routes:insert {
        hosts = { "acl7.com" },
      }

      bp.plugins:insert {
        name = "acl",
        route = { id = route7.id },
        config = {
          whitelist = { "admin", "pro", "hello" }
        }
      }

      bp.plugins:insert {
        name = "key-auth",
        route = { id = route7.id },
        config = {}
      }

      local route7b = bp.routes:insert {
        hosts = { "acl7b.com" },
      }

      bp.plugins:insert {
        name = "acl",
        route = { id = route7b.id },
        config = {
          whitelist = { "admin", "pro", "hello" }
        }
      }

      bp.plugins:insert {
        name = "ctx-checker",
        route = { id = route7b.id },
        config = {
          ctx_kind      = "kong.ctx.shared",
          ctx_set_field = "authenticated_groups",
          ctx_set_array = { "free", "hello" },
        }
      }

      local route8 = bp.routes:insert {
        hosts = { "acl8.com" },
      }

      bp.plugins:insert {
        name = "acl",
        route = { id = route8.id },
        config = {
          whitelist = { "anonymous" }
        }
      }

      bp.plugins:insert {
        name = "key-auth",
        route = { id = route8.id },
        config = {
          anonymous = anonymous.id,
        }
      }

      local route8b = bp.routes:insert {
        hosts = { "acl8b.com" },
      }

      bp.plugins:insert {
        name = "acl",
        route = { id = route8b.id },
        config = {
          whitelist = { "anonymous" }
        }
      }

      bp.plugins:insert {
        name = "key-auth",
        route = { id = route8b.id },
        config = {
          anonymous = anonymous.id,
        }
      }

      bp.plugins:insert {
        name = "ctx-checker",
        route = { id = route8b.id },
        config = {
          ctx_kind      = "kong.ctx.shared",
          ctx_set_field = "authenticated_groups",
          ctx_set_array = { "anonymous" },
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

      local route9b = bp.routes:insert {
        hosts = { "acl9b.com" },
      }

      bp.plugins:insert {
        name = "acl",
        route = { id = route9b.id },
        config = {
          whitelist = { "admin" },
          hide_groups_header = true
        }
      }

      bp.plugins:insert {
        name = "ctx-checker",
        route = { id = route9b.id },
        config = {
          ctx_kind      = "kong.ctx.shared",
          ctx_set_field = "authenticated_groups",
          ctx_set_array = { "admin" },
        }
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

      local route10b = bp.routes:insert {
        hosts = { "acl10b.com" },
      }

      bp.plugins:insert {
        name = "acl",
        route = { id = route10b.id },
        config = {
          whitelist = { "admin" },
          hide_groups_header = false
        }
      }

      bp.plugins:insert {
        name = "ctx-checker",
        route = { id = route10b.id },
        config = {
          ctx_kind      = "kong.ctx.shared",
          ctx_set_field = "authenticated_groups",
          ctx_set_array = { "admin" },
        }
      }

      local route11 = bp.routes:insert {
        hosts = { "acl11.com" },
      }

      bp.plugins:insert {
        name = "acl",
        route = { id = route11.id },
        config = {
          whitelist = { "admin", "anonymous" },
          hide_groups_header = false
        }
      }

      bp.plugins:insert {
        name = "key-auth",
        route = { id = route11.id },
        config = {
          anonymous = anonymous.id,
        }
      }

      bp.plugins:insert {
        name = "ctx-checker",
        route = { id = route11.id },
        config = {
          ctx_kind      = "kong.ctx.shared",
          ctx_set_field = "authenticated_groups",
          ctx_set_array = { "admin" },
        }
      }

      local route12 = bp.routes:insert {
        hosts = { "acl12.com" },
      }

      bp.plugins:insert {
        name = "acl",
        route = { id = route12.id },
        config = {
          whitelist = { "anonymous" },
          hide_groups_header = false
        }
      }

      bp.plugins:insert {
        name = "key-auth",
        route = { id = route12.id },
        config = {
          anonymous = anonymous.id,
        }
      }

      bp.plugins:insert {
        name = "ctx-checker",
        route = { id = route12.id },
        config = {
          ctx_kind      = "kong.ctx.shared",
          ctx_set_field = "authenticated_groups",
          ctx_set_array = { "anonymous" },
        }
      }

      local route13 = bp.routes:insert {
        hosts = { "acl13.com" },
      }

      bp.plugins:insert {
        name = "acl",
        route = { id = route13.id },
        config = {
          whitelist = { "anonymous" },
          hide_groups_header = false
        }
      }

      bp.plugins:insert {
        name = "key-auth",
        route = { id = route13.id },
        config = {
          anonymous = anonymous.id,
        }
      }

      bp.plugins:insert {
        name = "ctx-checker",
        route = { id = route13.id },
        config = {
          ctx_kind      = "kong.ctx.shared",
          ctx_set_field = "authenticated_groups",
          ctx_set_array = { "admin" },
        }
      }

      assert(helpers.start_kong({
        plugins    = "bundled, ctx-checker",
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


    describe("Mapping to Consumer or Authenticated Groups", function()
      it("should work with consumer with credentials", function()
        local res = assert(proxy_client:get("/request?apikey=apikey124", {
          headers = {
            ["Host"] = "acl2.com"
          }
        }))

        local body = cjson.decode(assert.res_status(200, res))
        assert.equal("admin", body.headers["x-consumer-groups"])
        assert.equal(nil, body.headers["x-authenticated-groups"])
      end)

      it("should work with authenticated groups", function()
        local res = assert(proxy_client:get("/request", {
          headers = {
            ["Host"] = "acl2b.com"
          }
        }))

        local body = cjson.decode(assert.res_status(200, res))
        assert.equal("admin", body.headers["x-authenticated-groups"])
        assert.equal(nil, body.headers["x-consumer-groups"])
      end)

      it("should work with consumer without credentials", function()
        local res = assert(proxy_client:get("/request", {
          headers = {
            ["Host"] = "acl8.com"
          }
        }))

        local body = cjson.decode(assert.res_status(200, res))
        assert.equal("anonymous", body.headers["x-consumer-groups"])
        assert.equal(nil, body.headers["x-authenticated-groups"])
      end)

      it("should work with authenticated groups without credentials", function()
        local res = assert(proxy_client:get("/request", {
          headers = {
            ["Host"] = "acl8b.com"
          }
        }))

        local body = cjson.decode(assert.res_status(200, res))
        assert.equal("anonymous", body.headers["x-authenticated-groups"])
        assert.equal(nil, body.headers["x-consumer-groups"])
      end)

    end)

    describe("Simple lists", function()
      it("should fail when an authentication plugin is missing", function()
        local res = assert(proxy_client:get("/status/200", {
          headers = {
            ["Host"] = "acl1.com"
          }
        }))
        local body = assert.res_status(403, res)
        local json = cjson.decode(body)
        assert.same({ message = "You cannot consume this service" }, json)
      end)

      it("should fail when not in whitelist", function()
        local res = assert(proxy_client:get("/status/200?apikey=apikey123", {
          headers = {
            ["Host"] = "acl2.com"
          }
        }))
        local body = assert.res_status(403, res)
        local json = cjson.decode(body)
        assert.same({ message = "You cannot consume this service" }, json)
      end)

      it("should fail when not in whitelist with authenticated groups", function()
        local res = assert(proxy_client:get("/status/200", {
          headers = {
            ["Host"] = "acl2c.com"
          }
        }))
        local body = assert.res_status(403, res)
        local json = cjson.decode(body)
        assert.same({ message = "You cannot consume this service" }, json)
      end)

      it("should work when in whitelist", function()
        local res = assert(proxy_client:get("/request?apikey=apikey124", {
          headers = {
            ["Host"] = "acl2.com"
          }
        }))
        local body = cjson.decode(assert.res_status(200, res))
        assert.equal("admin", body.headers["x-consumer-groups"])
        assert.equal(nil, body.headers["x-authenticated-groups"])
      end)

      it("should work when in whitelist with authenticated groups", function()
        local res = assert(proxy_client:get("/request", {
          headers = {
            ["Host"] = "acl2b.com"
          }
        }))
        local body = cjson.decode(assert.res_status(200, res))
        assert.equal("admin", body.headers["x-authenticated-groups"])
        assert.equal(nil, body.headers["x-consumer-groups"])
      end)

      it("should not send x-consumer-groups header when hide_groups_header flag true", function()
        local res = assert(proxy_client:get("/request?apikey=apikey124", {
          headers = {
            ["Host"] = "acl9.com"
          }
        }))
        local body = cjson.decode(assert.res_status(200, res))
        assert.equal(nil, body.headers["x-consumer-groups"])
        assert.equal(nil, body.headers["x-authenticated-groups"])
      end)

      it("should not send x-authenticated-groups header when hide_groups_header flag true", function()
        local res = assert(proxy_client:get("/request", {
          headers = {
            ["Host"] = "acl9b.com"
          }
        }))
        local body = cjson.decode(assert.res_status(200, res))
        assert.equal(nil, body.headers["x-consumer-groups"])
        assert.equal(nil, body.headers["x-authenticated-groups"])
      end)

      it("should send x-consumer-groups header when hide_groups_header flag false", function()
        local res = assert(proxy_client:get("/request?apikey=apikey124", {
          headers = {
            ["Host"] = "acl10.com"
          }
        }))
        local body = cjson.decode(assert.res_status(200, res))
        assert.equal("admin", body.headers["x-consumer-groups"])
        assert.equal(nil, body.headers["x-authenticated-groups"])
      end)

      it("should send x-authenticated-groups header when hide_groups_header flag false", function()
        local res = assert(proxy_client:get("/request", {
          headers = {
            ["Host"] = "acl10b.com"
          }
        }))
        local body = cjson.decode(assert.res_status(200, res))
        assert.equal("admin", body.headers["x-authenticated-groups"])
        assert.equal(nil, body.headers["x-consumer-groups"])
      end)

      it("should work when not in blacklist", function()
        local res = assert(proxy_client:get("/request?apikey=apikey123", {
          headers = {
            ["Host"] = "acl3.com"
          }
        }))
        assert.res_status(200, res)
      end)

      it("should work when not in blacklist with authenticated groups", function()
        local res = assert(proxy_client:get("/request", {
          headers = {
            ["Host"] = "acl3b.com"
          }
        }))
        assert.res_status(200, res)
      end)

      it("should fail when in blacklist", function()
        local res = assert(proxy_client:get("/request?apikey=apikey124", {
          headers = {
            ["Host"] = "acl3.com"
          }
        }))
        local body = assert.res_status(403, res)
        local json = cjson.decode(body)
        assert.same({ message = "You cannot consume this service" }, json)
      end)

      it("should fail when in blacklist with authenticated groups", function()
        local res = assert(proxy_client:get("/request", {
          headers = {
            ["Host"] = "acl3c.com"
          }
        }))
        local body = assert.res_status(403, res)
        local json = cjson.decode(body)
        assert.same({ message = "You cannot consume this service" }, json)
      end)
    end)

    describe("Multi lists", function()
      it("should work when in whitelist", function()
        local res = assert(proxy_client:get("/request?apikey=apikey125", {
          headers = {
            ["Host"] = "acl4.com"
          }
        }))
        local body = cjson.decode(assert.res_status(200, res))
        assert.True(body.headers["x-consumer-groups"] == "pro, hello" or body.headers["x-consumer-groups"] == "hello, pro")
        assert.equal(nil, body.headers["x-authenticated-groups"])
      end)

      it("should work when in whitelist with authenticated groups", function()
        local res = assert(proxy_client:get("/request", {
          headers = {
            ["Host"] = "acl4b.com"
          }
        }))
        local body = cjson.decode(assert.res_status(200, res))
        assert.True(body.headers["x-authenticated-groups"] == "pro, hello" or body.headers["x-consumer-groups"] == "hello, pro")
        assert.equal(nil, body.headers["x-consumer-groups"])
      end)

      it("should fail when not in whitelist", function()
        local res = assert(proxy_client:get("/request?apikey=apikey126", {
          headers = {
            ["Host"] = "acl4.com"
          }
        }))
        local body = assert.res_status(403, res)
        local json = cjson.decode(body)
        assert.same({ message = "You cannot consume this service" }, json)
      end)

      it("should fail when not in whitelist with authenticated groups", function()
        local res = assert(proxy_client:get("/request", {
          headers = {
            ["Host"] = "acl4c.com"
          }
        }))
        local body = assert.res_status(403, res)
        local json = cjson.decode(body)
        assert.same({ message = "You cannot consume this service" }, json)
      end)

      it("should fail when in blacklist", function()
        local res = assert(proxy_client:get("/request?apikey=apikey125", {
          headers = {
            ["Host"] = "acl5.com"
          }
        }))
        local body = assert.res_status(403, res)
        local json = cjson.decode(body)
        assert.same({ message = "You cannot consume this service" }, json)
      end)

      it("should fail when in blacklist with authenticated groups", function()
        local res = assert(proxy_client:get("/request", {
          headers = {
            ["Host"] = "acl5b.com"
          }
        }))
        local body = assert.res_status(403, res)
        local json = cjson.decode(body)
        assert.same({ message = "You cannot consume this service" }, json)
      end)


      it("should work when not in blacklist", function()
        local res = assert(proxy_client:get("/request?apikey=apikey126", {
          headers = {
            ["Host"] = "acl5.com"
          }
        }))
        assert.res_status(200, res)
      end)

      it("should work when not in blacklist with authenticated groups", function()
        local res = assert(proxy_client:get("/request", {
          headers = {
            ["Host"] = "acl5c.com"
          }
        }))
        assert.res_status(200, res)
      end)

      it("should not work when one of the ACLs in the blacklist", function()
        local res = assert(proxy_client:get("/request?apikey=apikey126", {
          headers = {
            ["Host"] = "acl6.com"
          }
        }))
        local body = assert.res_status(403, res)
        local json = cjson.decode(body)
        assert.same({ message = "You cannot consume this service" }, json)
      end)

      it("should not work when one of the ACLs in the blacklist with authenticated groups", function()
        local res = assert(proxy_client:get("/request", {
          headers = {
            ["Host"] = "acl6b.com"
          }
        }))
        local body = assert.res_status(403, res)
        local json = cjson.decode(body)
        assert.same({ message = "You cannot consume this service" }, json)
      end)

      it("should work when one of the ACLs in the whitelist", function()
        local res = assert(proxy_client:get("/request?apikey=apikey126", {
          headers = {
            ["Host"] = "acl7.com"
          }
        }))
        assert.res_status(200, res)
      end)

      it("should work when one of the ACLs in the whitelist with authenticated groups", function()
        local res = assert(proxy_client:get("/request", {
          headers = {
            ["Host"] = "acl7b.com"
          }
        }))
        assert.res_status(200, res)
      end)

      it("should not work when at least one of the ACLs in the blacklist", function()
        local res = assert(proxy_client:get("/request?apikey=apikey125", {
          headers = {
            ["Host"] = "acl6.com"
          }
        }))
        local body = assert.res_status(403, res)
        local json = cjson.decode(body)
        assert.same({ message = "You cannot consume this service" }, json)
      end)

      it("should not work when at least one of the ACLs in the blacklist with authenticated groups", function()
        local res = assert(proxy_client:get("/request", {
          headers = {
            ["Host"] = "acl6c.com"
          }
        }))
        local body = assert.res_status(403, res)
        local json = cjson.decode(body)
        assert.same({ message = "You cannot consume this service" }, json)
      end)
    end)

    describe("Real-world usage", function()
      it("should not fail when multiple rules are set fast", function()
        -- Create consumer
        local res = assert(admin_client:post("/consumers/", {
          headers = {
            ["Content-Type"] = "application/json"
          },
          body = {
            username = "acl_consumer"
          }
        }))
        local body = cjson.decode(assert.res_status(201, res))
        local consumer = { id = body.id }

        -- Create key
        local res = assert(admin_client:post("/consumers/acl_consumer/key-auth", {
          headers = {
            ["Content-Type"] = "application/json"
          },
          body = {
            key = "secret123"
          }
        }))
        assert.res_status(201, res)

        for i = 1, 3 do
          -- Create API
          local service = bp.services:insert()

          local res = assert(admin_client:post("/routes", {
            headers = {
              ["Content-Type"] = "application/json"
            },
            body = {
              hosts     = { "acl_test" .. i .. ".com" },
              protocols = { "http", "https" },
              service   = {
                id = service.id
              },
            },
          }))

          local body = assert.res_status(201, res)
          local json = cjson.decode(body)

          -- Add the ACL plugin to the new API with the new group
          local res = assert(admin_client:post("/plugins", {
            headers = {
              ["Content-Type"] = "application/json"
            },
            body = {
              name   = "acl",
              config = { whitelist = { "admin" .. i } },
              route  = { id = json.id },
            }
          }))

          assert.res_status(201, res)

          -- Add key-authentication to API
          local res = assert(admin_client:post("/plugins", {
            headers = {
              ["Content-Type"] = "application/json"
            },
            body = {
              name  = "key-auth",
              route = { id = json.id },
            }
          }))
          assert.res_status(201, res)

          -- Add a new group to the consumer
          local res = assert(admin_client:post("/consumers/acl_consumer/acls", {
            headers = {
              ["Content-Type"] = "application/json"
            },
            body = {
              group = "admin" .. i
            }
          }))
          assert.res_status(201, res)

          -- Wait for cache to be invalidated
          local cache_key = db.acls:cache_key(consumer)

          helpers.wait_for_invalidation(cache_key)

          -- Make the request, and it should work

          local res
          helpers.wait_until(function()
            res = assert(proxy_client:get("/status/200?apikey=secret123", {
              headers = {
                ["Host"] = "acl_test" .. i .. ".com"
              }
            }))
            res:read_body()
            return res.status ~= 404
          end, 5)

          assert.res_status(200, res)
        end
      end)
      it("should not fail when multiple rules are set fast with authenticated groups", function()
        for i = 1, 3 do
          -- Create API
          local service = bp.services:insert()

          local res = assert(admin_client:post("/routes/", {
            headers = {
              ["Content-Type"] = "application/json"
            },
            body = {
              hosts     = { "acl_test" .. i .. "b.com" },
              protocols = { "http", "https" },
              service   = {
                id = service.id
              },
            },
          }))

          local body = assert.res_status(201, res)
          local json = cjson.decode(body)

          -- Add the ACL plugin to the new API with the new group
          local res = assert(admin_client:post("/plugins", {
            headers = {
              ["Content-Type"] = "application/json"
            },
            body = {
              name   = "acl",
              config = { whitelist = { "admin" .. i } },
              route  = { id = json.id },
            }
          }))

          assert.res_status(201, res)

          -- Add key-authentication to API
          local res = assert(admin_client:post("/plugins", {
            headers = {
              ["Content-Type"] = "application/json"
            },
            body = {
              name  = "ctx-checker",
              route = { id = json.id },
              config = {
                ctx_kind      = "kong.ctx.shared",
                ctx_set_field = "authenticated_groups",
                ctx_set_array = { "admin" .. i },
              }
            }
          }))
          assert.res_status(201, res)

          -- Make the request, and it should work
          local res
          helpers.wait_until(function()
            res = assert(proxy_client:get("/status/200", {
              headers = {
                ["Host"] = "acl_test" .. i .. "b.com"
              }
            }))
            res:read_body()
            return res.status ~= 404
          end, 5)

          assert.res_status(200, res)
        end
      end)
    end)

    describe("Permits with", function()
      it("authenticated consumer even when authorized groups are present", function()
        local res = assert(proxy_client:get("/request?apikey=apikey124", {
          headers = {
            ["Host"] = "acl11.com"
          }
        }))
        local body = cjson.decode(assert.res_status(200, res))
        assert.equal("admin", body.headers["x-consumer-groups"])
        assert.equal(nil, body.headers["x-authenticated-groups"])
      end)

      it("authorized groups even when anonymous consumer is present", function()
        local res = assert(proxy_client:get("/request", {
          headers = {
            ["Host"] = "acl11.com"
          }
        }))
        local body = cjson.decode(assert.res_status(200, res))
        assert.equal("admin", body.headers["x-authenticated-groups"])
        assert.equal(nil, body.headers["x-consumer-groups"])
      end)
    end)

    describe("Forbids with", function()
      it("authenticated consumer even when authorized groups are present", function()
        local res = assert(proxy_client:get("/request?apikey=apikey124", {
          headers = {
            ["Host"] = "acl12.com"
          }
        }))
        local body = assert.res_status(403, res)
        local json = cjson.decode(body)
        assert.same({ message = "You cannot consume this service" }, json)
      end)

      it("authorized groups even when anonymous consumer is present", function()
        local res = assert(proxy_client:get("/request", {
          headers = {
            ["Host"] = "acl13.com"
          }
        }))
        local body = assert.res_status(403, res)
        local json = cjson.decode(body)
        assert.same({ message = "You cannot consume this service" }, json)
      end)
    end)
  end)
end
