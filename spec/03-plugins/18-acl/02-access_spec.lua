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
        hosts = { "acl1.test" },
      }

      bp.plugins:insert {
        name = "acl",
        route = { id = route1.id },
        config = {
          allow = { "admin" },
        }
      }

      local route1b = bp.routes:insert {
        hosts = { "acl1b.test" },
      }

      bp.plugins:insert {
        name = "acl",
        route = { id = route1b.id },
        config = {
          allow = { "admin" },
        }
      }

      bp.plugins:insert {
        name = "ctx-checker",
        route = { id = route1b.id },
        config = {
          ctx_set_field = "authenticated_credential",
          ctx_set_value = "dummy-credential",
        }
      }

      local route2 = bp.routes:insert {
        hosts = { "acl2.test" },
      }

      bp.plugins:insert {
        name = "acl",
        route = { id = route2.id },
        config = {
          allow = { "admin" },
        }
      }

      bp.plugins:insert {
        name = "key-auth",
        route = { id = route2.id },
        config = {}
      }

      local route2b = bp.routes:insert {
        hosts = { "acl2b.test" },
      }

      bp.plugins:insert {
        name = "acl",
        route = { id = route2b.id },
        config = {
          allow = { "admin" },
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
        hosts = { "acl2c.test" },
      }

      bp.plugins:insert {
        name = "acl",
        route = { id = route2c.id },
        config = {
          allow = { "admin" },
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
        hosts = { "acl3.test" },
      }

      bp.plugins:insert {
        name = "acl",
        route = { id = route3.id },
        config = {
          deny = { "admin" }
        }
      }

      bp.plugins:insert {
        name = "key-auth",
        route = { id = route3.id },
        config = {}
      }

      local route3b = bp.routes:insert {
        hosts = { "acl3b.test" },
      }

      bp.plugins:insert {
        name = "acl",
        route = { id = route3b.id },
        config = {
          deny = { "admin" }
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
        hosts = { "acl3c.test" },
      }

      bp.plugins:insert {
        name = "acl",
        route = { id = route3c.id },
        config = {
          deny = { "admin" }
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

      local route3d = bp.routes:insert {
        hosts = { "acl3d.test" },
      }

      bp.plugins:insert {
        name = "acl",
        route = { id = route3d.id },
        config = {
          deny = { "none" }
        }
      }

      local route4 = bp.routes:insert {
        hosts = { "acl4.test" },
      }

      bp.plugins:insert {
        name = "acl",
        route = { id = route4.id },
        config = {
          allow = { "admin", "pro" }
        }
      }

      bp.plugins:insert {
        name = "key-auth",
        route = { id = route4.id },
        config = {}
      }

      local route4b = bp.routes:insert {
        hosts = { "acl4b.test" },
      }

      bp.plugins:insert {
        name = "acl",
        route = { id = route4b.id },
        config = {
          allow = { "admin", "pro" }
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
        hosts = { "acl4c.test" },
      }

      bp.plugins:insert {
        name = "acl",
        route = { id = route4c.id },
        config = {
          allow = { "admin", "pro" }
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
        hosts = { "acl5.test" },
      }

      bp.plugins:insert {
        name = "acl",
        route = { id = route5.id },
        config = {
          deny = { "admin", "pro" }
        }
      }

      bp.plugins:insert {
        name = "key-auth",
        route = { id = route5.id },
        config = {}
      }

      local route5b = bp.routes:insert {
        hosts = { "acl5b.test" },
      }

      bp.plugins:insert {
        name = "acl",
        route = { id = route5b.id },
        config = {
          deny = { "admin", "pro" }
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
        hosts = { "acl5c.test" },
      }

      bp.plugins:insert {
        name = "acl",
        route = { id = route5c.id },
        config = {
          deny = { "admin", "pro" }
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
        hosts = { "acl6.test" },
      }

      bp.plugins:insert {
        name = "acl",
        route = { id = route6.id },
        config = {
          deny = { "admin", "pro", "hello" }
        }
      }

      bp.plugins:insert {
        name = "key-auth",
        route = { id = route6.id },
        config = {}
      }

      local route6b = bp.routes:insert {
        hosts = { "acl6b.test" },
      }

      bp.plugins:insert {
        name = "acl",
        route = { id = route6b.id },
        config = {
          deny = { "admin", "pro", "hello" }
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
        hosts = { "acl6c.test" },
      }

      bp.plugins:insert {
        name = "acl",
        route = { id = route6c.id },
        config = {
          deny = { "admin", "pro", "hello" }
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
        hosts = { "acl7.test" },
      }

      bp.plugins:insert {
        name = "acl",
        route = { id = route7.id },
        config = {
          allow = { "admin", "pro", "hello" }
        }
      }

      bp.plugins:insert {
        name = "key-auth",
        route = { id = route7.id },
        config = {}
      }

      local route7b = bp.routes:insert {
        hosts = { "acl7b.test" },
      }

      bp.plugins:insert {
        name = "acl",
        route = { id = route7b.id },
        config = {
          allow = { "admin", "pro", "hello" }
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
        hosts = { "acl8.test" },
      }

      bp.plugins:insert {
        name = "acl",
        route = { id = route8.id },
        config = {
          allow = { "anonymous" }
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
        hosts = { "acl8b.test" },
      }

      bp.plugins:insert {
        name = "acl",
        route = { id = route8b.id },
        config = {
          allow = { "anonymous" }
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
        hosts = { "acl9.test" },
      }

      bp.plugins:insert {
        name = "acl",
        route = { id = route9.id },
        config = {
          allow = { "admin" },
          hide_groups_header = true
        }
      }

      bp.plugins:insert {
        name = "key-auth",
        route = { id = route9.id },
        config = {}
      }

      local route9b = bp.routes:insert {
        hosts = { "acl9b.test" },
      }

      bp.plugins:insert {
        name = "acl",
        route = { id = route9b.id },
        config = {
          allow = { "admin" },
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
        hosts = { "acl10.test" },
      }

      bp.plugins:insert {
        name = "acl",
        route = { id = route10.id },
        config = {
          allow = { "admin" },
          hide_groups_header = false
        }
      }

      bp.plugins:insert {
        name = "key-auth",
        route = { id = route10.id },
        config = {}
      }

      local route10b = bp.routes:insert {
        hosts = { "acl10b.test" },
      }

      bp.plugins:insert {
        name = "acl",
        route = { id = route10b.id },
        config = {
          allow = { "admin" },
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
        hosts = { "acl11.test" },
      }

      bp.plugins:insert {
        name = "acl",
        route = { id = route11.id },
        config = {
          allow = { "admin", "anonymous" },
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
        hosts = { "acl12.test" },
      }

      bp.plugins:insert {
        name = "acl",
        route = { id = route12.id },
        config = {
          allow = { "anonymous" },
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
        hosts = { "acl13.test" },
      }

      bp.plugins:insert {
        name = "acl",
        route = { id = route13.id },
        config = {
          allow = { "anonymous" },
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

      local route14 = bp.routes:insert({
        hosts = { "acl14.test" }
      })

      local acl_prefunction_code = "        local consumer_id = \"" .. tostring(consumer2.id) .. "\"\n" .. [[
        local cache_key = kong.db.acls:cache_key(consumer_id)

        -- we must use shadict to get the cache, because the `kong.cache` was hooked by `kong.plugins.pre-function` 
        local raw_groups, err = ngx.shared.kong_db_cache:get("kong_db_cache"..cache_key)
        if raw_groups then
          ngx.exit(200)
        else
          ngx.log(ngx.ERR, "failed to get cache: ", err)
          ngx.exit(500)
        end
          
      ]]

      bp.plugins:insert {
        route = { id = route14.id },
        name = "pre-function",
        config = {
          access = {
            acl_prefunction_code,
          },
        }
      }

      assert(helpers.start_kong({
        plugins    = "bundled, ctx-checker",
        database   = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
        db_cache_warmup_entities = "keyauth_credentials,consumers,acls",
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
            ["Host"] = "acl2.test"
          }
        }))

        local body = cjson.decode(assert.res_status(200, res))
        assert.equal("admin", body.headers["x-consumer-groups"])
        assert.equal(nil, body.headers["x-authenticated-groups"])
      end)

      it("should work with authenticated groups", function()
        local res = assert(proxy_client:get("/request", {
          headers = {
            ["Host"] = "acl2b.test"
          }
        }))

        local body = cjson.decode(assert.res_status(200, res))
        assert.equal("admin", body.headers["x-authenticated-groups"])
        assert.equal(nil, body.headers["x-consumer-groups"])
      end)

      it("should work with consumer without credentials", function()
        local res = assert(proxy_client:get("/request", {
          headers = {
            ["Host"] = "acl8.test"
          }
        }))

        local body = cjson.decode(assert.res_status(200, res))
        assert.equal("anonymous", body.headers["x-consumer-groups"])
        assert.equal(nil, body.headers["x-authenticated-groups"])
      end)

      it("should work with authenticated groups without credentials", function()
        local res = assert(proxy_client:get("/request", {
          headers = {
            ["Host"] = "acl8b.test"
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
            ["Host"] = "acl1.test"
          }
        }))
        local body = assert.res_status(401, res)
        local json = cjson.decode(body)
        assert.not_nil(json)
        assert.matches("Unauthorized", json.message)
      end)

      it("should fail when an authentication plugin is missing (with credential)", function()
        local res = assert(proxy_client:get("/status/200", {
          headers = {
            ["Host"] = "acl1b.test"
          }
        }))
        local body = assert.res_status(403, res)
        local json = cjson.decode(body)
        assert.not_nil(json)
        assert.matches("You cannot consume this service", json.message)
      end)

      it("should fail when not allowed", function()
        local res = assert(proxy_client:get("/status/200?apikey=apikey123", {
          headers = {
            ["Host"] = "acl2.test"
          }
        }))
        local body = assert.res_status(403, res)
        local json = cjson.decode(body)
        assert.not_nil(json)
        assert.matches("You cannot consume this service", json.message)
      end)

      it("should fail when not allowed with authenticated groups", function()
        local res = assert(proxy_client:get("/status/200", {
          headers = {
            ["Host"] = "acl2c.test"
          }
        }))
        local body = assert.res_status(403, res)
        local json = cjson.decode(body)
        assert.not_nil(json)
        assert.matches("You cannot consume this service", json.message)
      end)

      it("should work when allowed", function()
        local res = assert(proxy_client:get("/request?apikey=apikey124", {
          headers = {
            ["Host"] = "acl2.test"
          }
        }))
        local body = cjson.decode(assert.res_status(200, res))
        assert.equal("admin", body.headers["x-consumer-groups"])
        assert.equal(nil, body.headers["x-authenticated-groups"])
      end)

      it("should work when allowed with authenticated groups", function()
        local res = assert(proxy_client:get("/request", {
          headers = {
            ["Host"] = "acl2b.test"
          }
        }))
        local body = cjson.decode(assert.res_status(200, res))
        assert.equal("admin", body.headers["x-authenticated-groups"])
        assert.equal(nil, body.headers["x-consumer-groups"])
      end)

      it("should not send x-consumer-groups header when hide_groups_header flag true", function()
        local res = assert(proxy_client:get("/request?apikey=apikey124", {
          headers = {
            ["Host"] = "acl9.test"
          }
        }))
        local body = cjson.decode(assert.res_status(200, res))
        assert.equal(nil, body.headers["x-consumer-groups"])
        assert.equal(nil, body.headers["x-authenticated-groups"])
      end)

      it("should not send x-authenticated-groups header when hide_groups_header flag true", function()
        local res = assert(proxy_client:get("/request", {
          headers = {
            ["Host"] = "acl9b.test"
          }
        }))
        local body = cjson.decode(assert.res_status(200, res))
        assert.equal(nil, body.headers["x-consumer-groups"])
        assert.equal(nil, body.headers["x-authenticated-groups"])
      end)

      it("should send x-consumer-groups header when hide_groups_header flag false", function()
        local res = assert(proxy_client:get("/request?apikey=apikey124", {
          headers = {
            ["Host"] = "acl10.test"
          }
        }))
        local body = cjson.decode(assert.res_status(200, res))
        assert.equal("admin", body.headers["x-consumer-groups"])
        assert.equal(nil, body.headers["x-authenticated-groups"])
      end)

      it("should send x-authenticated-groups header when hide_groups_header flag false", function()
        local res = assert(proxy_client:get("/request", {
          headers = {
            ["Host"] = "acl10b.test"
          }
        }))
        local body = cjson.decode(assert.res_status(200, res))
        assert.equal("admin", body.headers["x-authenticated-groups"])
        assert.equal(nil, body.headers["x-consumer-groups"])
      end)

      it("should work when not denied", function()
        local res = assert(proxy_client:get("/request?apikey=apikey123", {
          headers = {
            ["Host"] = "acl3.test"
          }
        }))
        assert.res_status(200, res)
      end)

      it("should work when not denied with authenticated groups", function()
        local res = assert(proxy_client:get("/request", {
          headers = {
            ["Host"] = "acl3b.test"
          }
        }))
        assert.res_status(200, res)
      end)

      it("should fail when denied", function()
        local res = assert(proxy_client:get("/request?apikey=apikey124", {
          headers = {
            ["Host"] = "acl3.test"
          }
        }))
        local body = assert.res_status(403, res)
        local json = cjson.decode(body)
        assert.not_nil(json)
        assert.matches("You cannot consume this service", json.message)
      end)

      it("should fail when denied with authenticated groups", function()
        local res = assert(proxy_client:get("/request", {
          headers = {
            ["Host"] = "acl3c.test"
          }
        }))
        local body = assert.res_status(403, res)
        local json = cjson.decode(body)
        assert.not_nil(json)
        assert.matches("You cannot consume this service", json.message)
      end)

      it("should fail denied and with no authenticated groups", function()
        local res = assert(proxy_client:get("/request", {
          headers = {
            ["Host"] = "acl3d.test"
          }
        }))
        local body = assert.res_status(401, res)
        local json = cjson.decode(body)
        assert.not_nil(json)
        assert.matches("Unauthorized", json.message)
      end)
    end)

    describe("Multi lists", function()
      it("should work when allowed", function()
        local res = assert(proxy_client:get("/request?apikey=apikey125", {
          headers = {
            ["Host"] = "acl4.test"
          }
        }))
        local body = cjson.decode(assert.res_status(200, res))
        assert.True(body.headers["x-consumer-groups"] == "pro, hello" or body.headers["x-consumer-groups"] == "hello, pro")
        assert.equal(nil, body.headers["x-authenticated-groups"])
      end)

      it("should work when allowed with authenticated groups", function()
        local res = assert(proxy_client:get("/request", {
          headers = {
            ["Host"] = "acl4b.test"
          }
        }))
        local body = cjson.decode(assert.res_status(200, res))
        assert.True(body.headers["x-authenticated-groups"] == "pro, hello" or body.headers["x-consumer-groups"] == "hello, pro")
        assert.equal(nil, body.headers["x-consumer-groups"])
      end)

      it("should fail when not allowed", function()
        local res = assert(proxy_client:get("/request?apikey=apikey126", {
          headers = {
            ["Host"] = "acl4.test"
          }
        }))
        local body = assert.res_status(403, res)
        local json = cjson.decode(body)
        assert.not_nil(json)
        assert.matches("You cannot consume this service", json.message)
      end)

      it("should fail when not allowed with authenticated groups", function()
        local res = assert(proxy_client:get("/request", {
          headers = {
            ["Host"] = "acl4c.test"
          }
        }))
        local body = assert.res_status(403, res)
        local json = cjson.decode(body)
        assert.not_nil(json)
        assert.matches("You cannot consume this service", json.message)
      end)

      it("should fail when denied", function()
        local res = assert(proxy_client:get("/request?apikey=apikey125", {
          headers = {
            ["Host"] = "acl5.test"
          }
        }))
        local body = assert.res_status(403, res)
        local json = cjson.decode(body)
        assert.not_nil(json)
        assert.matches("You cannot consume this service", json.message)
      end)

      it("should fail when denied with authenticated groups", function()
        local res = assert(proxy_client:get("/request", {
          headers = {
            ["Host"] = "acl5b.test"
          }
        }))
        local body = assert.res_status(403, res)
        local json = cjson.decode(body)
        assert.not_nil(json)
        assert.matches("You cannot consume this service", json.message)
      end)


      it("should work when not denied", function()
        local res = assert(proxy_client:get("/request?apikey=apikey126", {
          headers = {
            ["Host"] = "acl5.test"
          }
        }))
        assert.res_status(200, res)
      end)

      it("should work when not denied with authenticated groups", function()
        local res = assert(proxy_client:get("/request", {
          headers = {
            ["Host"] = "acl5c.test"
          }
        }))
        assert.res_status(200, res)
      end)

      it("should not work when one of the ACLs denied", function()
        local res = assert(proxy_client:get("/request?apikey=apikey126", {
          headers = {
            ["Host"] = "acl6.test"
          }
        }))
        local body = assert.res_status(403, res)
        local json = cjson.decode(body)
        assert.not_nil(json)
        assert.matches("You cannot consume this service", json.message)
      end)

      it("should not work when one of the ACLs denied with authenticated groups", function()
        local res = assert(proxy_client:get("/request", {
          headers = {
            ["Host"] = "acl6b.test"
          }
        }))
        local body = assert.res_status(403, res)
        local json = cjson.decode(body)
        assert.not_nil(json)
        assert.matches("You cannot consume this service", json.message)
      end)

      it("should work when one of the ACLs is allowed", function()
        local res = assert(proxy_client:get("/request?apikey=apikey126", {
          headers = {
            ["Host"] = "acl7.test"
          }
        }))
        assert.res_status(200, res)
      end)

      it("should work when one of the ACLs is allowed with authenticated groups", function()
        local res = assert(proxy_client:get("/request", {
          headers = {
            ["Host"] = "acl7b.test"
          }
        }))
        assert.res_status(200, res)
      end)

      it("should not work when at least one of the ACLs denied", function()
        local res = assert(proxy_client:get("/request?apikey=apikey125", {
          headers = {
            ["Host"] = "acl6.test"
          }
        }))
        local body = assert.res_status(403, res)
        local json = cjson.decode(body)
        assert.not_nil(json)
        assert.matches("You cannot consume this service", json.message)
      end)

      it("should not work when at least one of the ACLs denied with authenticated groups", function()
        local res = assert(proxy_client:get("/request", {
          headers = {
            ["Host"] = "acl6c.test"
          }
        }))
        local body = assert.res_status(403, res)
        local json = cjson.decode(body)
        assert.not_nil(json)
        assert.matches("You cannot consume this service", json.message)
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
              hosts     = { "acl_test" .. i .. ".test" },
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
              config = { allow = { "admin" .. i } },
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
                ["Host"] = "acl_test" .. i .. ".test"
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
              hosts     = { "acl_test" .. i .. "b.test" },
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
              config = { allow = { "admin" .. i } },
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
                ["Host"] = "acl_test" .. i .. "b.test"
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
            ["Host"] = "acl11.test"
          }
        }))
        local body = cjson.decode(assert.res_status(200, res))
        assert.equal("admin", body.headers["x-consumer-groups"])
        assert.equal(nil, body.headers["x-authenticated-groups"])
      end)

      it("authorized groups even when anonymous consumer is present", function()
        local res = assert(proxy_client:get("/request", {
          headers = {
            ["Host"] = "acl11.test"
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
            ["Host"] = "acl12.test"
          }
        }))
        local body = assert.res_status(403, res)
        local json = cjson.decode(body)
        assert.not_nil(json)
        assert.matches("You cannot consume this service", json.message)
      end)

      it("authorized groups even when anonymous consumer is present", function()
        local res = assert(proxy_client:get("/request", {
          headers = {
            ["Host"] = "acl13.test"
          }
        }))
        local body = assert.res_status(403, res)
        local json = cjson.decode(body)
        assert.not_nil(json)
        assert.matches("You cannot consume this service", json.message)
      end)
    end)

    describe("cache warmup acls group", function()
      it("cache warmup acls group", function()
        assert(helpers.restart_kong {
          plugins    = "bundled, ctx-checker",
          database   = strategy,
          nginx_conf = "spec/fixtures/custom_nginx.template",
          db_cache_warmup_entities = "keyauth_credentials,consumers,acls",
        })

        proxy_client = helpers.proxy_client()
        local res = assert(proxy_client:get("/request", {
          headers = {
            ["Host"] = "acl14.test"
          }
        }))
        assert.res_status(200, res)
      end)
    end)
  
  end)

  describe("Plugin: ACL (access) [#" .. strategy .. "] anonymous", function()
    local proxy_client
    local admin_client
    local bp

    lazy_setup(function()
      bp = helpers.get_db_utils(strategy, {
        "routes",
        "services",
        "plugins",
        "consumers",
        "acls",
        "keyauth_credentials",
      }, { "ctx-checker" })

      local anonymous = bp.consumers:insert {
        username = "anonymous",
      }

      local anonymous_with_group = bp.consumers:insert {
        username = "anonymous_with_group",
      }
      bp.acls:insert {
        group    = "everyone",
        consumer = { id = anonymous_with_group.id },
      }

      do
        local allow_everyone = bp.routes:insert {
          hosts = { "allow-everyone.test" },
        }
        bp.plugins:insert {
          name = "acl",
          route = { id = allow_everyone.id },
          config = {
            allow = { "everyone" },
          },
        }
      end

      do
        local allow_none = bp.routes:insert {
          hosts = { "allow-none.test" },
        }
        bp.plugins:insert {
          name = "acl",
          route = { id = allow_none.id },
          config = {
            allow = { "none" },
          },
        }
      end

      do
        local deny_everyone = bp.routes:insert {
          hosts = { "deny-everyone.test" },
        }
        bp.plugins:insert {
          name = "acl",
          route = { id = deny_everyone.id },
          config = {
            allow = { "everyone" },
          },
        }
      end

      do
        local deny_none = bp.routes:insert {
          hosts = { "deny-none.test" },
        }
        bp.plugins:insert {
          name = "acl",
          route = { id = deny_none.id },
          config = {
            allow = { "none" },
          },
        }
      end

      do
        local allow_everyone_anonymous = bp.routes:insert {
          hosts = { "allow-everyone-anonymous.test" },
        }
        bp.plugins:insert {
          name = "acl",
          route = { id = allow_everyone_anonymous.id },
          config = {
            allow = { "everyone" },
          },
        }
        bp.plugins:insert {
          name = "key-auth",
          route = { id = allow_everyone_anonymous.id },
          config = {
            anonymous = anonymous.id,
          }
        }
      end

      do
        local allow_everyone_anonymous_with_group = bp.routes:insert {
          hosts = { "allow-everyone-anonymous-with-group.test" },
        }
        bp.plugins:insert {
          name = "acl",
          route = { id = allow_everyone_anonymous_with_group.id },
          config = {
            allow = { "everyone" },
          },
        }
        bp.plugins:insert {
          name = "key-auth",
          route = { id = allow_everyone_anonymous_with_group.id },
          config = {
            anonymous = anonymous_with_group.id,
          }
        }
      end

      do
        local allow_none_anonymous = bp.routes:insert {
          hosts = { "allow-none-anonymous.test" },
        }
        bp.plugins:insert {
          name = "acl",
          route = { id = allow_none_anonymous.id },
          config = {
            allow = { "none" },
          },
        }
        bp.plugins:insert {
          name = "key-auth",
          route = { id = allow_none_anonymous.id },
          config = {
            anonymous = anonymous.id,
          }
        }
      end

      do
        local allow_none_anonymous_with_group = bp.routes:insert {
          hosts = { "allow-none-anonymous-with-group.test" },
        }
        bp.plugins:insert {
          name = "acl",
          route = { id = allow_none_anonymous_with_group.id },
          config = {
            allow = { "none" },
          },
        }
        bp.plugins:insert {
          name = "key-auth",
          route = { id = allow_none_anonymous_with_group.id },
          config = {
            anonymous = anonymous_with_group.id,
          }
        }
      end

      do
        local deny_everyone_anonymous = bp.routes:insert {
          hosts = { "deny-everyone-anonymous.test" },
        }
        bp.plugins:insert {
          name = "acl",
          route = { id = deny_everyone_anonymous.id },
          config = {
            deny = { "everyone" },
          },
        }
        bp.plugins:insert {
          name = "key-auth",
          route = { id = deny_everyone_anonymous.id },
          config = {
            anonymous = anonymous.id,
          }
        }
      end

      do
        local deny_everyone_anonymous_with_group = bp.routes:insert {
          hosts = { "deny-everyone-anonymous-with-group.test" },
        }
        bp.plugins:insert {
          name = "acl",
          route = { id = deny_everyone_anonymous_with_group.id },
          config = {
            deny = { "everyone" },
          },
        }
        bp.plugins:insert {
          name = "key-auth",
          route = { id = deny_everyone_anonymous_with_group.id },
          config = {
            anonymous = anonymous_with_group.id,
          }
        }
      end

      do
        local deny_none_anonymous = bp.routes:insert {
          hosts = { "deny-none-anonymous.test" },
        }
        bp.plugins:insert {
          name = "acl",
          route = { id = deny_none_anonymous.id },
          config = {
            deny = { "none" },
          },
        }
        bp.plugins:insert {
          name = "key-auth",
          route = { id = deny_none_anonymous.id },
          config = {
            anonymous = anonymous.id,
          }
        }
      end

      do
        local deny_none_anonymous_with_group = bp.routes:insert {
          hosts = { "deny-none-anonymous-with-group.test" },
        }
        bp.plugins:insert {
          name = "acl",
          route = { id = deny_none_anonymous_with_group.id },
          config = {
            deny = { "none" },
          },
        }
        bp.plugins:insert {
          name = "key-auth",
          route = { id = deny_none_anonymous_with_group.id },
          config = {
            anonymous = anonymous_with_group.id,
          }
        }
      end

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

    describe("without authentication", function()
      it("returns 401", function()
        local res = assert(proxy_client:get("/request", {
          headers = {
            Host = "allow-everyone.test"
          }
        }))
        local body = cjson.decode(assert.res_status(401, res))
        assert.equal(nil, body.headers)
        assert.equal("Unauthorized", body.message)

        local res = assert(proxy_client:get("/request", {
          headers = {
            Host = "allow-none.test"
          }
        }))
        local body = cjson.decode(assert.res_status(401, res))
        assert.equal(nil, body.headers)
        assert.equal("Unauthorized", body.message)

        local res = assert(proxy_client:get("/request", {
          headers = {
            Host = "deny-everyone.test"
          }
        }))
        local body = cjson.decode(assert.res_status(401, res))
        assert.equal(nil, body.headers)
        assert.equal("Unauthorized", body.message)

        local res = assert(proxy_client:get("/request", {
          headers = {
            Host = "deny-none.test"
          }
        }))
        local body = cjson.decode(assert.res_status(401, res))
        assert.equal(nil, body.headers)
        assert.equal("Unauthorized", body.message)
      end)
    end)

    describe("with authentication without groups", function()
      it("returns 401 with allow groups", function()
        local res = assert(proxy_client:get("/request", {
          headers = {
            Host = "allow-everyone-anonymous.test"
          }
        }))
        local body = cjson.decode(assert.res_status(401, res))
        assert.equal(nil, body.headers)
        assert.equal("Unauthorized", body.message)

        local res = assert(proxy_client:get("/request", {
          headers = {
            Host = "allow-none-anonymous.test"
          }
        }))
        local body = cjson.decode(assert.res_status(401, res))
        assert.equal(nil, body.headers)
        assert.equal("Unauthorized", body.message)
      end)

      it("returns 200 with deny groups", function()
        local res = assert(proxy_client:get("/request", {
          headers = {
            Host = "deny-everyone-anonymous.test"
          }
        }))
        local body = cjson.decode(assert.res_status(200, res))
        assert.equal("", body.headers["x-consumer-groups"])

        local res = assert(proxy_client:get("/request", {
          headers = {
            Host = "deny-none-anonymous.test"
          }
        }))
        local body = cjson.decode(assert.res_status(200, res))
        assert.equal("", body.headers["x-consumer-groups"])
      end)
    end)

    describe("with authentication with group", function()
      it("returns 200", function()
        local res = assert(proxy_client:get("/request", {
          headers = {
            Host = "allow-everyone-anonymous-with-group.test"
          }
        }))
        local body = cjson.decode(assert.res_status(200, res))
        assert.equal(nil, body.headers["x-authenticated-groups"])
        assert.equal("everyone", body.headers["x-consumer-groups"])

        local res = assert(proxy_client:get("/request", {
          headers = {
            Host = "deny-none-anonymous-with-group.test"
          }
        }))
        local body = cjson.decode(assert.res_status(200, res))
        assert.equal(nil, body.headers["x-authenticated-groups"])
        assert.equal("everyone", body.headers["x-consumer-groups"])
      end)

      it("returns 403", function()
        local res = assert(proxy_client:get("/request", {
          headers = {
            Host = "allow-none-anonymous-with-group.test"
          }
        }))
        local body = cjson.decode(assert.res_status(403, res))
        assert.equal(nil, body.headers)
        assert.equal("You cannot consume this service", body.message)

        local res = assert(proxy_client:get("/request", {
          headers = {
            Host = "deny-everyone-anonymous-with-group.test"
          }
        }))
        local body = cjson.decode(assert.res_status(403, res))
        assert.equal(nil, body.headers)
        assert.equal("You cannot consume this service", body.message)
      end)
    end)
  end)
end
