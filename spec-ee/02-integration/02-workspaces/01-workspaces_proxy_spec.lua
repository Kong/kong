local helpers = require "spec.helpers"

for _, strategy in helpers.each_strategy() do
  describe("Plugin execution is restricted to correct workspace #" .. strategy, function()
    local proxy_client

    setup(function()
      local bp = helpers.get_db_utils(strategy)

      bp.routes:insert {
        paths = {
          "/default",
        }
      }

      bp.plugins:insert {
        name = "key-auth",
      }

      local c1 = bp.consumers:insert {
        username = "c1",
      }

      bp.keyauth_credentials:insert {
        key = "c1key",
        consumer = { id = c1.id },
      }

      -- create a route in a different workspace [[

      local ws = bp.workspaces:insert {
        name = "ws1",
      }

      bp.routes:insert_ws({
        paths = {
          "/ws1"
        }
      }, ws)

      -- ]]

      assert(helpers.start_kong({
        database   = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
        db_update_propagation = strategy == "cassandra" and 3 or 0
      }))
      proxy_client = helpers.proxy_client()
    end)

    teardown(function()
      helpers.stop_kong(nil, true)
    end)

    it("Triggers plugin if it's in current request's workspaces", function()
      local res = assert(proxy_client:send {
        method = "GET",
        path = "/default/status/200",
      })
      -- 401 means keyauth was triggered; as there's no apikey in the request,
      -- the plugin returns 401
      assert.res_status(401, res)

      local res = assert(proxy_client:send {
        method = "GET",
        path = "/default/status/200",
        headers = {
          apikey = "c1key",
        }
      })
      -- 200 means keyauth was triggered; as there's a valid apikey in the request,
      -- we get the expected upstream response
      assert.res_status(200, res)
    end)

    it("Doesn't trigger another workspace's plugin", function()
      local res = assert(proxy_client:send {
        method = "GET",
        path = "/ws1/status/200",
      })

      -- 200 means keyauth wasn't triggered
      assert.res_status(200, res)
    end)
  end)
  describe("Plugin: workspace scope test key-auth (access) #" .. strategy, function()
    local admin_client, proxy_client, route1, plugin_foo, ws_foo, ws_default, db, bp, s
    local consumer_default, cred_default
    setup(function()
      bp, db = helpers.get_db_utils(strategy)

      ws_default = assert(db.workspaces:select_by_name("default"))

      assert(helpers.start_kong({
        database   = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
        db_update_propagation = strategy == "cassandra" and 3 or 0
      }))
      admin_client = helpers.admin_client()
      proxy_client = helpers.proxy_client()

      ws_foo = bp.workspaces:insert({name = "foo"})
      s = bp.services:insert({name = "s1"})

      local res = admin_client:post("/services/s1/routes",
        {
          body   = {
            hosts = {"route1.com"},
          },
          headers = {
            ["Content-Type"] = "application/json",
        }}
      )
      assert.res_status(201, res)
      route1 = assert.response(res).has.jsonbody()

      res = admin_client:post("/services/s1/plugins", {
        body = {name = "key-auth"},
        headers =  {["Content-Type"] = "application/json"},
      })
      assert.res_status(201, res)


      consumer_default = bp.consumers:insert({username = "bob"})

      res = admin_client:post("/consumers/" .. consumer_default.username .. "/key-auth", {
        body   = {
          key = "kong",
        },
        headers = {
          ["Content-Type"] = "application/json",
        }
      })
      assert.res_status(201, res)
      cred_default = assert.response(res).has.jsonbody()

      admin_client:close()
    end)
    teardown(function()
      helpers.stop_kong(nil, true)
    end)

    before_each(function()
      admin_client = helpers.admin_client()
      proxy_client = helpers.proxy_client()
    end)

    after_each(function()
      admin_client:close()
      proxy_client:close()
    end)

    describe("test sharing route1 with foo", function()
      it("without sharing", function()
        local res = assert(proxy_client:send {
          method = "GET",
          path = "/anything",
          headers = {
            ["Host"] = "route1.com",
            ["apikey"] = "kong",
          }
        })
        assert.res_status(200, res)
      end)
      it("should not allow workspace prefix in key", function()
        local res = assert(proxy_client:send {
          method = "GET",
          path = "/anything",
          headers = {
            ["Host"] = "route1.com",
            ["apikey"] = "default:kong",
          }
        })
        assert.res_status(403, res)
      end)
      it("cache added for plugin in default workspace", function()
        local cache_key = db.plugins:cache_key_ws(ws_default,
                                                   "key-auth",
                                                   nil,
                                                   s.id,
                                                   nil,
                                                   nil)
        local res
        helpers.wait_until(function()
          res = admin_client:get("/cache/" .. cache_key)
          res:read_body()
          return res.status == 200
        end)

        local body = assert.response(res).has.jsonbody()
        assert.is_equal(ws_default.id, body.workspace_id)

        local cache_key = db.keyauth_credentials:cache_key(cred_default.key)
        local res
        helpers.wait_until(function()
          res = admin_client:send {
            method = "GET",
            path = "/cache/" .. cache_key,
          }
          assert(res)
          return res.status == 200
        end)

        local body = assert.response(res).has.jsonbody()
        assert.is_equal(cred_default.id, body.id)

        local cache_key = db.consumers:cache_key(consumer_default.id)
        local res
        helpers.wait_until(function()
          res = assert(admin_client:send {
            method = "GET",
            path = "/cache/" .. cache_key,
          })
          return res.status == 200
        end)

        local body = assert.response(res).has.jsonbody()
        assert.is_equal(cred_default.consumer.id, body.id)
      end)
      it("negative cache not added for non enabled plugin", function()
        local cache_key = db.plugins:cache_key_ws(nil,
                                                   "request-transformer",
                                                   nil,
                                                   nil,
                                                   nil,
                                                   route1.id)

        local res
        helpers.wait_until(function()
          res = assert(admin_client:send {
            method = "GET",
            path = "/cache/" .. cache_key,
          })
          return res.status == 404
        end)

        assert.response(res).has.jsonbody()
      end)
      it("share service with foo", function()

        local res = assert(admin_client:send {
          method = "POST",
          path   = "/workspaces/foo/entities",
          body   = {
            entities = s.id,
          },
          headers = {
            ["Content-Type"] = "application/json",
          }
        })
        assert.res_status(201, res)

        local res = assert(admin_client:send {
          method = "POST",
          path   = "/workspaces/foo/entities",
          body   = {
            entities = route1.id,
          },
          headers = {
            ["Content-Type"] = "application/json",
          }
        })
        assert.res_status(201, res)

        local res = assert(proxy_client:send {
          method = "GET",
          path = "/anything",
          headers = {
            ["Host"] = "route1.com",
            ["apikey"] = "kong",
          }
        })
        assert.res_status(200, res)
      end)
      it("add request-transformer on foo side", function()
        local res = assert(admin_client:send {
          method = "POST",
          path   = "/foo/services/" .. s.name .. "/plugins" ,
          body   = {
            name = "request-transformer",
            config = {
              add = {
                headers = {"X-TEST:ok"}
              }
            }
          },
          headers = {
            ["Content-Type"] = "application/json",
          }
        })
        assert.res_status(201, res)
        plugin_foo = assert.response(res).has.jsonbody()

        local res = assert(proxy_client:send {
          method = "GET",
          path = "/anything",
          headers = {
            ["Host"] = "route1.com",
            ["apikey"] = "kong",
          }
        })
        assert.res_status(200, res)
        local body = assert.response(res).has.jsonbody()
        assert.equals("ok", body.headers["x-test"])
      end)
      it("cache added for plugin in foo workspace", function()
        local cache_key = db.plugins:cache_key_ws(ws_foo,
                                                   "request-transformer",
                                                   nil,
                                                   s.id,
                                                   nil,
                                                   nil)

        local res
        helpers.wait_until(function()
          res = assert(admin_client:send {
            method = "GET",
            path = "/cache/" .. cache_key,
          })
          res:read_body()
          return res.status == 200
        end)

        local body = assert.response(res).has.jsonbody()
        assert.is_equal(ws_foo.id, body.workspace_id)

      end)
      it("negative cache added for non enabled plugin in default workspace", function()
        local cache_key = db.plugins:cache_key_ws(ws_default,
                                                   "request-transformer",
                                                   nil,
                                                   s.id,
                                                   nil,
                                                   nil)

        local res
        helpers.wait_until(function()
          res = assert(admin_client:send {
            method = "GET",
            path = "/cache/" .. cache_key,
          })
          return res.status == 200
        end, 7)

        local content = res:read_body()
        assert.is_equal("", content)
      end)
      it("delete plugin on foo side", function()
        local res = assert(admin_client:send {
          method = "DELETE",
          path   = "/foo/plugins/" .. plugin_foo.id ,
        })
        assert.res_status(204, res)

        local res = assert(proxy_client:send {
          method = "GET",
          path = "/anything",
          headers = {
            ["Host"] = "route1.com",
            ["apikey"] = "kong",
          }
        })
        assert.res_status(200, res)
        local body = assert.response(res).has.jsonbody()
        assert.is_nil(body.headers["x-test"])
      end)
      it("cache not added for plugin in foo workspace", function()
        local cache_key = db.plugins:cache_key_ws(nil,
                                                   "request-transformer",
                                                   nil,
                                                   s.id,
                                                   nil,
                                                   nil)

        local res
        helpers.wait_until(function()
          res = assert(admin_client:send {
            method = "GET",
            path = "/cache/" .. cache_key,
          })
          return res.status == 404
        end, 7)
        assert.response(res).has.jsonbody()
      end)
    end)
  end)
end
