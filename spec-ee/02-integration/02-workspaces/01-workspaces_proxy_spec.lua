local helpers = require "spec.helpers"

for _, strategy in helpers.each_strategy() do
  describe("Plugin execution is restricted to correct workspace", function()
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
        consumer_id = c1.id,
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
  describe("Plugin: workspace scope test key-auth (access)", function()
    local admin_client, proxy_client, api1, plugin_foo, ws_foo, ws_default, dao
    local consumer_default, cred_default
    setup(function()
      dao = select(3, helpers.get_db_utils(strategy))

      ws_default = dao.workspaces:find_all({name = "default"})[1]


      assert(helpers.start_kong({
        database   = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
        db_update_propagation = strategy == "cassandra" and 3 or 0
      }))
      admin_client = helpers.admin_client()
      proxy_client = helpers.proxy_client()

      local res = assert(admin_client:send {
        method = "POST",
        path   = "/workspaces",
        body   = {
          name = "foo",
        },
        headers = {
          ["Content-Type"] = "application/json",
        }
      })
      assert.res_status(201, res)
      ws_foo = assert.response(res).has.jsonbody()

      local res = assert(admin_client:send {
        method = "POST",
        path   = "/workspaces",
        body   = {
          name = "bar",
        },
        headers = {
          ["Content-Type"] = "application/json",
        }
      })
      assert.res_status(201, res)

      local res = assert(admin_client:send {
        method = "POST",
        path   = "/apis",
        body   = {
          name = "test",
          upstream_url = helpers.mock_upstream_url,
          hosts = "api1.com"
        },
        headers = {
          ["Content-Type"] = "application/json",
        }
      })
      assert.res_status(201, res)
      api1 = assert.response(res).has.jsonbody()


      local res = assert(admin_client:send {
        method = "POST",
        path   = "/apis/" .. api1.name .. "/plugins" ,
        body   = {
          name = "key-auth",
        },
        headers = {
          ["Content-Type"] = "application/json",
        }
      })
      assert.res_status(201, res)

      local res = assert(admin_client:send {
        method = "POST",
        path   = "/consumers" ,
        body   = {
          username = "bob",
        },
        headers = {
          ["Content-Type"] = "application/json",
        }
      })
      assert.res_status(201, res)
      consumer_default = assert.response(res).has.jsonbody()

      local res = assert(admin_client:send {
        method = "POST",
        path   = "/consumers/" .. consumer_default.username .. "/key-auth"   ,
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

    describe("test sharing api1 with foo", function()
      it("withoud sharing", function()
        local res = assert(proxy_client:send {
          method = "GET",
          path = "/anything",
          headers = {
            ["Host"] = "api1.com",
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
            ["Host"] = "api1.com",
            ["apikey"] = "default:kong",
          }
        })
        assert.res_status(403, res)
      end)
      it("cache added for plugin in default workspace", function()
        local cache_key = dao.plugins:cache_key_ws(ws_default,
                                                   "key-auth",
                                                   nil,
                                                   nil,
                                                   nil,
                                                   api1.id)
        local res
        helpers.wait_until(function()
          res = assert(admin_client:send {
            method = "GET",
            path = "/cache/" .. cache_key,
          })
          return res.status == 200
        end)

        local body = assert.response(res).has.jsonbody()
        assert.is_equal(ws_default.id, body.workspace_id)

        local cache_key = dao.keyauth_credentials:cache_key(cred_default.key)
        local res
        helpers.wait_until(function()
          res = assert(admin_client:send {
            method = "GET",
            path = "/cache/" .. cache_key,
          })
          return res.status == 200
        end)

        local body = assert.response(res).has.jsonbody()
        assert.is_equal(cred_default.id, body.id)

        local cache_key = dao.consumers:cache_key(consumer_default.id)
        local res
        helpers.wait_until(function()
          res = assert(admin_client:send {
            method = "GET",
            path = "/cache/" .. cache_key,
          })
          return res.status == 200
        end)

        local body = assert.response(res).has.jsonbody()
        assert.is_equal(cred_default.consumer_id, body.id)
      end)
      it("negative cache not added for non enabled plugin", function()
        local cache_key = dao.plugins:cache_key_ws(nil,
                                                   "request-transformer",
                                                   nil,
                                                   nil,
                                                   nil,
                                                   api1.id)

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
      it("share api with foo", function()
        local res = assert(admin_client:send {
          method = "POST",
          path   = "/workspaces/foo/entities",
          body   = {
            entities = api1.id,
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
            ["Host"] = "api1.com",
            ["apikey"] = "kong",
          }
        })
        assert.res_status(200, res)
      end)
      it("add request-transformer on foo side", function()
        local res = assert(admin_client:send {
          method = "POST",
          path   = "/foo/apis/" .. api1.name .. "/plugins" ,
          body   = {
            name = "request-transformer",
            config = {
              add = {
                headers = "X-TEST:ok"
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
            ["Host"] = "api1.com",
            ["apikey"] = "kong",
          }
        })
        assert.res_status(200, res)
        local body = assert.response(res).has.jsonbody()
        assert.equals("ok", body.headers["x-test"])
      end)
      it("cache added for plugin in foo workspace", function()
        local cache_key = dao.plugins:cache_key_ws(ws_foo,
                                                   "request-transformer",
                                                   nil,
                                                   nil,
                                                   nil,
                                                   api1.id)

        local res
        helpers.wait_until(function()
          res = assert(admin_client:send {
            method = "GET",
            path = "/cache/" .. cache_key,
          })
          return res.status == 200
        end)

        local body = assert.response(res).has.jsonbody()
        assert.is_equal(ws_foo.id, body.workspace_id)

      end)
      it("negative cache added for non enabled plugin in default workspace", function()
        local cache_key = dao.plugins:cache_key_ws(ws_default,
                                                   "request-transformer",
                                                   nil,
                                                   nil,
                                                   nil,
                                                   api1.id)

        local res
        helpers.wait_until(function()
          res = assert(admin_client:send {
            method = "GET",
            path = "/cache/" .. cache_key,
          })
          return res.status == 200
        end, 7)

        local body = assert.response(res).has.jsonbody()
        assert.is_equal(true, body.null)
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
            ["Host"] = "api1.com",
            ["apikey"] = "kong",
          }
        })
        assert.res_status(200, res)
        local body = assert.response(res).has.jsonbody()
        assert.is_nil(body.headers["x-test"])
      end)
      it("cache not added for plugin in foo workspace", function()
        local cache_key = dao.plugins:cache_key_ws(nil,
                                                   "request-transformer",
                                                   nil,
                                                   nil,
                                                   nil,
                                                   api1.id)

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
