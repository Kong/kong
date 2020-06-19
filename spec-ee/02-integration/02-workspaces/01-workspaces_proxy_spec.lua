local helpers = require "spec.helpers"
local run_ws = require "kong.workspaces".run_with_ws_scope
local utils = require "kong.tools.utils"
local pl_path = require "pl.path"
local pl_file = require "pl.file"
local pl_stringx = require "pl.stringx"
local cjson = require "cjson"


local LOG_WAIT_TIMEOUT = 10


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
        assert.res_status(401, res)
      end)
      it("cache added for plugin in default workspace", function()
        local cache_key = db.plugins:cache_key("key-auth",
                                                nil,
                                                s.id,
                                                nil,
                                                nil,
                                                false)
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
        local cache_key = db.plugins:cache_key("request-transformer",
                                                nil,
                                                nil,
                                                nil,
                                                route1.id,
                                                false)

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
         local cache_key = run_ws({ ws_foo }, function()
          return db.plugins:cache_key("request-transformer",
                                      nil,
                                      s.id,
                                      nil,
                                      nil,
                                      false)
        end)

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
      -- marked as pending as negative cache is now lazy loaded
      pending("negative cache added for non enabled plugin in default workspace", function()
        local cache_key = db.plugins:cache_key("request-transformer",
                                                nil,
                                                s.id,
                                                nil,
                                                nil,
                                                false)

        local res
        helpers.wait_until(function()
          res = assert(admin_client:send {
            method = "GET",
            path = "/cache/" .. cache_key,
          })
          return res.status == 200
        end, 7)

        local content = res:read_body()
        assert.is_equal("{}", content)
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
        local cache_key = db.plugins:cache_key("request-transformer",
                                                nil,
                                                s.id,
                                                nil,
                                                nil,
                                                true)
        cache_key = cache_key .. ws_foo.id

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
  describe("proxy-intercepted error #" .. strategy, function()
    local FILE_LOG_PATH_DEFAULT = os.tmpname()
    local FILE_LOG_PATH_FOO = os.tmpname()
    local FILE_LOG_PATH = os.tmpname()
    local proxy_client

    lazy_setup(function()
      local bp = helpers.get_db_utils(strategy, {
        "routes",
        "services",
        "plugins",
      }, {
        "error-handler-log",
      })

      local ws_foo = bp.workspaces:insert({name = "foo"})
      do
        -- service to mock HTTP 502
        local mock_service_default = bp.services:insert {
          name            = "timeout",
          host            = "httpbin.org",
          connect_timeout = 1, -- ms
        }

        bp.routes:insert {
          hosts     = { "timeout-default" },
          protocols = { "http" },
          service   = mock_service_default,
        }

        bp.plugins:insert {
          name     = "file-log",
          service  = { id = mock_service_default.id },
          config   = {
            path   = FILE_LOG_PATH_DEFAULT,
            reopen = true,
          }
        }

        local mock_service_foo = bp.services:insert_ws( {
          name            = "timeout",
          host            = "httpbin.org",
          connect_timeout = 1, -- ms
        }, ws_foo)

        bp.routes:insert_ws({
          hosts     = { "timeout-foo" },
          protocols = { "http" },
          service   = mock_service_foo,
        }, ws_foo)

        bp.plugins:insert_ws( {
          name     = "file-log",
          service  = { id = mock_service_foo.id },
          config   = {
            path   = FILE_LOG_PATH_FOO,
            reopen = true,
          }
        }, ws_foo)
      end

      do
        -- global plugin to catch Nginx-produced client errors
        -- added in default ws
        bp.plugins:insert {
          name = "file-log",
          config = {
            path = FILE_LOG_PATH,
            reopen = true,
          }
        }

        -- global plugin to catch Nginx-produced client errors
        -- added in foo ws
        bp.plugins:insert_ws ({
          name = "error-handler-log",
          config = {},
        }, ws_foo)
      end

      -- start mock httpbin instance
      assert(helpers.start_kong {
        database = strategy,
        admin_listen = "127.0.0.1:9011",
        proxy_listen = "127.0.0.1:9010",
        proxy_listen_ssl = "127.0.0.1:9453",
        admin_listen_ssl = "127.0.0.1:9454",
        prefix = "servroot2",
        nginx_conf = "spec/fixtures/custom_nginx.template",
      })

      -- start Kong instance with our services and plugins
      assert(helpers.start_kong {
        database = strategy,
        db_update_propagation = strategy == "cassandra" and 3 or 0
      })
    end)


    lazy_teardown(function()
      helpers.stop_kong("servroot2")
      helpers.stop_kong()
    end)


    before_each(function()
      proxy_client = helpers.proxy_client()
      pl_file.delete(FILE_LOG_PATH_DEFAULT)
      pl_file.delete(FILE_LOG_PATH_FOO)
      pl_file.delete(FILE_LOG_PATH)
    end)


    after_each(function()
      if proxy_client then
        proxy_client:close()
      end
    end)


    it("executes ws default plugins on Bad Gateway (HTTP 504)", function()
      -- triggers error_page directive
      local uuid = utils.uuid()

      local res = assert(proxy_client:send {
        method = "GET",
        path = "/status/200",
        headers = {
          ["Host"] = "timeout-default",
          ["X-UUID"] = uuid,
        }
      })
      assert.res_status(504, res) -- Bad Gateway
      -- should not execute foo workspace plugin for server error
      assert.is_nil(res.headers["Log-Plugin-Phases"])

      -- TEST: ensure that our logging plugin was executed and wrote
      -- something to disk.

      helpers.wait_until(function()
        return pl_path.exists(FILE_LOG_PATH_DEFAULT)
          and pl_path.getsize(FILE_LOG_PATH_DEFAULT) > 0
      end, LOG_WAIT_TIMEOUT)

      local log = pl_file.read(FILE_LOG_PATH_DEFAULT)
      local log_message = cjson.decode(pl_stringx.strip(log))
      assert.equal("127.0.0.1", log_message.client_ip)
      assert.equal(uuid, log_message.request.headers["x-uuid"])
    end)


    it("executes workspace foo plugins on Bad Gateway (HTTP 504)", function()
      -- triggers error_page directive
      local uuid = utils.uuid()

      local res = assert(proxy_client:send {
        method = "GET",
        path = "/status/200",
        headers = {
          ["Host"] = "timeout-foo",
          ["X-UUID"] = uuid,
        }
      })
      assert.res_status(504, res) -- Bad Gateway
      assert.equal("rewrite,access,header_filter", res.headers["Log-Plugin-Phases"])

      -- TEST: ensure that our logging plugin was executed and wrote
      -- something to disk.

      helpers.wait_until(function()
        return pl_path.exists(FILE_LOG_PATH_FOO)
          and pl_path.getsize(FILE_LOG_PATH_FOO) > 0
      end, LOG_WAIT_TIMEOUT)

      local log = pl_file.read(FILE_LOG_PATH_FOO)
      local log_message = cjson.decode(pl_stringx.strip(log))
      assert.equal("127.0.0.1", log_message.client_ip)
      assert.equal(uuid, log_message.request.headers["x-uuid"])
    end)


    it("executes global plugins on Nginx-produced client errors (HTTP 494) for default ws service", function()
      -- triggers error_page directive
      local uuid = utils.uuid()

      local res = assert(proxy_client:send {
        method = "GET",
        path = "/",
        headers = {
          ["Host"] = "refused",
          ["X-Large"] = string.rep("a", 2^10 * 10), -- default large_client_header_buffers is 8k
          ["X-UUID"] = uuid,
        }
      })
      assert.res_status(494, res)

      -- TEST: ensure that our logging plugin was executed and wrote
      -- something to disk.

      helpers.wait_until(function()
        return pl_path.exists(FILE_LOG_PATH)
          and pl_path.getsize(FILE_LOG_PATH) > 0
      end, LOG_WAIT_TIMEOUT)

      local log = pl_file.read(FILE_LOG_PATH)
      local log_message = cjson.decode(pl_stringx.strip(log))

      assert.equal(uuid, log_message.request.headers["x-uuid"])
      assert.equal("header_filter", res.headers["Log-Plugin-Phases"])
      assert.equal(494, log_message.response.status)
    end)

    it("executes global plugins from workspace default and foo on Nginx-produced client errors (HTTP 494) for foo ws service", function()
      local uuid = utils.uuid()

      local res = assert(proxy_client:send {
        method = "GET",
        path = "/",
        headers = {
          ["Host"] = "refused-foo",
          ["X-Large"] = string.rep("a", 2^10 * 10), -- default large_client_header_buffers is 8k
          ["X-UUID"] = uuid,
        }
      })
      assert.res_status(494, res)

      -- TEST: ensure that our logging plugin was executed and wrote
      -- something to disk.

      helpers.wait_until(function()
        return pl_path.exists(FILE_LOG_PATH)
          and pl_path.getsize(FILE_LOG_PATH) > 0
      end, LOG_WAIT_TIMEOUT)

      local log = pl_file.read(FILE_LOG_PATH)
      local log_message = cjson.decode(pl_stringx.strip(log))

      assert.equal(uuid, log_message.request.headers["x-uuid"])
      assert.equal("header_filter", res.headers["Log-Plugin-Phases"])
      assert.equal(494, log_message.response.status)
    end)
  end)

  describe("global plugin per workspace #" .. strategy, function()
    local FILE_LOG_PATH_DEFAULT = os.tmpname()
    local FILE_LOG_PATH_FOO = os.tmpname()
    local proxy_client

    lazy_setup(function()
      local bp = helpers.get_db_utils(strategy, {
        "routes",
        "services",
        "plugins",
      })

      local ws_foo = bp.workspaces:insert({name = "foo"})
      do
        local mock_service_default = bp.services:insert {
          name = "service-default"
        }

        bp.routes:insert {
          hosts     = { "service-default" },
          protocols = { "http" },
          service   = mock_service_default,
        }

        -- global plugin added in default ws
        bp.plugins:insert {
          name = "file-log",
          config = {
            path = FILE_LOG_PATH_DEFAULT,
            reopen = true,
          }
        }

        local mock_service_foo = bp.services:insert_ws( {
          name  = "service-foo",
        }, ws_foo)

        bp.routes:insert_ws({
          hosts     = { "service-foo" },
          protocols = { "http" },
          service   = mock_service_foo,
        }, ws_foo)

        -- global plugin added in foo ws

        bp.plugins:insert_ws( {
          name = "file-log",
          config = {
            path = FILE_LOG_PATH_FOO,
            reopen = true,
          }
        }, ws_foo)
      end

      -- start mock httpbin instance
      assert(helpers.start_kong {
        database = strategy,
        admin_listen = "127.0.0.1:9011",
        proxy_listen = "127.0.0.1:9010",
        proxy_listen_ssl = "127.0.0.1:9453",
        admin_listen_ssl = "127.0.0.1:9454",
        prefix = "servroot2",
        nginx_conf = "spec/fixtures/custom_nginx.template",
      })

      -- start Kong instance with our services and plugins
      assert(helpers.start_kong {
        database = strategy,
        db_update_propagation = strategy == "cassandra" and 3 or 0
      })
    end)


    lazy_teardown(function()
      helpers.stop_kong("servroot2")
      helpers.stop_kong()
    end)


    before_each(function()
      proxy_client = helpers.proxy_client()
      pl_file.delete(FILE_LOG_PATH_DEFAULT)
      pl_file.delete(FILE_LOG_PATH_FOO)
    end)


    after_each(function()
      pl_file.delete(FILE_LOG_PATH_DEFAULT)
      pl_file.delete(FILE_LOG_PATH_FOO)

      if proxy_client then
        proxy_client:close()
      end
    end)


    it("executes ws default plugin", function()
      -- triggers error_page directive
      local uuid = utils.uuid()

      local res = assert(proxy_client:send {
        method = "GET",
        path = "/status/200",
        headers = {
          ["Host"] = "service-default",
          ["X-UUID"] = uuid,
        }
      })
      assert.res_status(200, res) -- Bad Gateway

      -- TEST: ensure that our logging plugin was executed and wrote
      -- something to disk.

      helpers.wait_until(function()
        return pl_path.exists(FILE_LOG_PATH_DEFAULT)
          and pl_path.getsize(FILE_LOG_PATH_DEFAULT) > 0
      end, LOG_WAIT_TIMEOUT)

      local log = pl_file.read(FILE_LOG_PATH_DEFAULT)
      local log_message = cjson.decode(pl_stringx.strip(log))
      assert.equal("127.0.0.1", log_message.client_ip)
      assert.equal(uuid, log_message.request.headers["x-uuid"])
    end)


    it("executes ws foo plugin", function()
      -- triggers error_page directive
      local uuid = utils.uuid()

      local res = assert(proxy_client:send {
        method = "GET",
        path = "/status/200",
        headers = {
          ["Host"] = "service-foo",
          ["X-UUID"] = uuid,
        }
      })
      assert.res_status(200, res) -- Bad Gateway

      -- TEST: ensure that our logging plugin was executed and wrote
      -- something to disk.

      helpers.wait_until(function()
        return pl_path.exists(FILE_LOG_PATH_FOO)
          and pl_path.getsize(FILE_LOG_PATH_FOO) > 0
      end, LOG_WAIT_TIMEOUT)

      local log = pl_file.read(FILE_LOG_PATH_FOO)
      local log_message = cjson.decode(pl_stringx.strip(log))
      assert.equal("127.0.0.1", log_message.client_ip)
      assert.equal(uuid, log_message.request.headers["x-uuid"])
    end)
  end)
end
