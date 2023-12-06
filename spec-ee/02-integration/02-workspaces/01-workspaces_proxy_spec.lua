-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local utils = require "kong.tools.utils"
local pl_path = require "pl.path"
local pl_file = require "pl.file"
local pl_stringx = require "pl.stringx"
local cjson = require "cjson"
local http_mock = require "spec.helpers.http_mock"


local LOG_WAIT_TIMEOUT = 30
local MOCK_PORT = helpers.get_available_port()


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
    local admin_client, proxy_client, bp
    local consumer_default
    setup(function()
      bp = helpers.get_db_utils(strategy)

      assert(helpers.start_kong({
        database   = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }))
      admin_client = helpers.admin_client()
      proxy_client = helpers.proxy_client()

      bp.workspaces:insert({name = "foo"})
      bp.services:insert({name = "s1"})

      local res = admin_client:post("/services/s1/routes",
        {
          body   = {
            hosts = {"route1.test"},
          },
          headers = {
            ["Content-Type"] = "application/json",
        }}
      )
      assert.res_status(201, res)

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
      assert.response(res).has.jsonbody()

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
  end)

  describe("proxy-intercepted error #" .. strategy, function()
    local FILE_LOG_PATH_DEFAULT = os.tmpname()
    local FILE_LOG_PATH_A = os.tmpname()
    local FILE_LOG_PATH_B = os.tmpname()
    local FILE_LOG_PATH_GLOBAL_DEFAULT = os.tmpname()
    local proxy_client

    lazy_setup(function()
      local bp = helpers.get_db_utils(strategy, {
        "routes",
        "services",
        "plugins",
        "workspaces",
      }, {
        "error-handler-log",
      })

      do
        -- service to mock HTTP 504
        local mock_service_default = bp.services:insert {
          name            = "timeout",
          host            = "konghq.com",
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

        -- global plugin which runs on rewrite on default workspace
        bp.plugins:insert {
          name     = "error-handler-log",
          config   = {}
        }
      end

      local ws_a = bp.workspaces:insert({name = "ws_a"})
      do
        local mock_service_a = bp.services:insert_ws( {
          name            = "timeout",
          host            = "konghq.com",
          connect_timeout = 1, -- ms
        }, ws_a)

        bp.routes:insert_ws({
          hosts     = { "timeout-a" },
          protocols = { "http" },
          service   = mock_service_a,
        }, ws_a)

        bp.plugins:insert_ws( {
          name     = "file-log",
          service  = { id = mock_service_a.id },
          config   = {
            path   = FILE_LOG_PATH_A,
            reopen = true,
          }
        }, ws_a)
      end

      local ws_b = bp.workspaces:insert({name = "ws_b"})
      do
        local mock_service_b = bp.services:insert_ws( {
          name            = "timeout",
          host            = "konghq.com",
          connect_timeout = 1, -- ms
        }, ws_b)

        bp.routes:insert_ws({
          hosts     = { "timeout-b" },
          protocols = { "http" },
          service   = mock_service_b,
        }, ws_b)

        bp.plugins:insert_ws( {
          name     = "file-log",
          service  = { id = mock_service_b.id },
          config   = {
            path   = FILE_LOG_PATH_B,
            reopen = true,
          }
        }, ws_b)

        -- global plugin which doesn't run on rewrite on another workspace
        bp.plugins:insert_ws( {
          name     = "error-handler-log",
          config   = {}
        }, ws_b)
      end

      do
        -- global plugin to catch Nginx-produced client errors
        -- added in default ws
        bp.plugins:insert {
          name = "file-log",
          config = {
            path = FILE_LOG_PATH_GLOBAL_DEFAULT,
            reopen = true,
          }
        }
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
      })
    end)


    lazy_teardown(function()
      helpers.stop_kong("servroot2")
      helpers.stop_kong()
    end)


    before_each(function()
      proxy_client = helpers.proxy_client()
      pl_file.delete(FILE_LOG_PATH_DEFAULT)
      pl_file.delete(FILE_LOG_PATH_A)
      pl_file.delete(FILE_LOG_PATH_B)
      pl_file.delete(FILE_LOG_PATH_GLOBAL_DEFAULT)
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

      -- executes global plugin including rewrite phase
      assert.equal("rewrite,access,header_filter", res.headers["Log-Plugin-Phases"])

      -- executed file-log for default workspace
      helpers.wait_until(function()
        return pl_path.exists(FILE_LOG_PATH_DEFAULT)
          and pl_path.getsize(FILE_LOG_PATH_DEFAULT) > 0
      end, LOG_WAIT_TIMEOUT)

      local log = pl_file.read(FILE_LOG_PATH_DEFAULT)
      local log_message = cjson.decode(pl_stringx.strip(log):match("%b{}"))
      assert.equal("127.0.0.1", log_message.client_ip)
      assert.equal(uuid, log_message.request.headers["x-uuid"])
    end)

    it("executes workspace A plugins on Bad Gateway (HTTP 504)", function()
      -- triggers error_page directive
      local uuid = utils.uuid()

      local res = assert(proxy_client:send {
        method = "GET",
        path = "/status/200",
        headers = {
          ["Host"] = "timeout-a",
          ["X-UUID"] = uuid,
        }
      })
      assert.res_status(504, res) -- Bad Gateway

      -- does not execute global plugin from default workspace
      assert.equal(nil, res.headers["Log-Plugin-Phases"])

      -- TEST: ensure that our logging plugin was executed and wrote
      -- something to disk.

      helpers.wait_until(function()
        return pl_path.exists(FILE_LOG_PATH_A)
          and pl_path.getsize(FILE_LOG_PATH_A) > 0
      end, LOG_WAIT_TIMEOUT)

      local log = pl_file.read(FILE_LOG_PATH_A)
      local log_message = cjson.decode(pl_stringx.strip(log):match("%b{}"))
      assert.equal("127.0.0.1", log_message.client_ip)
      assert.equal(uuid, log_message.request.headers["x-uuid"])
    end)

    it("executes workspace B plugins on Bad Gateway (HTTP 504)", function()
      -- triggers error_page directive
      local uuid = utils.uuid()

      local res = assert(proxy_client:send {
        method = "GET",
        path = "/status/200",
        headers = {
          ["Host"] = "timeout-b",
          ["X-UUID"] = uuid,
        }
      })
      assert.res_status(504, res) -- Bad Gateway

      -- executes global plugin for B but not on the rewrite phase
      assert.equal("access,header_filter", res.headers["Log-Plugin-Phases"])

      -- TEST: ensure that our logging plugin was executed and wrote
      -- something to disk.

      helpers.wait_until(function()
        return pl_path.exists(FILE_LOG_PATH_B)
          and pl_path.getsize(FILE_LOG_PATH_B) > 0
      end, LOG_WAIT_TIMEOUT)

      local log = pl_file.read(FILE_LOG_PATH_B)
      local log_message = cjson.decode(pl_stringx.strip(log):match("%b{}"))
      assert.equal("127.0.0.1", log_message.client_ip)
      assert.equal(uuid, log_message.request.headers["x-uuid"])
    end)

    it("executes global plugins on Nginx-produced client errors (HTTP 400) for default ws service", function()
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
      assert.res_status(400, res)

      -- TEST: ensure that our logging plugin was executed and wrote
      -- something to disk.

      helpers.wait_until(function()
        return pl_path.exists(FILE_LOG_PATH_GLOBAL_DEFAULT)
          and pl_path.getsize(FILE_LOG_PATH_GLOBAL_DEFAULT) > 0
      end, LOG_WAIT_TIMEOUT)

      local log = pl_file.read(FILE_LOG_PATH_GLOBAL_DEFAULT)
      local log_message = cjson.decode(pl_stringx.strip(log):match("%b{}"))

      assert.equal("header_filter", res.headers["Log-Plugin-Phases"])
      assert.equal(400, log_message.response.status)
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
      local log_message = cjson.decode(pl_stringx.strip(log):match("%b{}"))
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
      local log_message = cjson.decode(pl_stringx.strip(log):match("%b{}"))
      assert.equal("127.0.0.1", log_message.client_ip)
      assert.equal(uuid, log_message.request.headers["x-uuid"])
    end)
  end)

  describe("Plugin execution out of its workspace scope #" .. strategy, function()
    local proxy_client, mock

    lazy_setup(function()
      local bp = helpers.get_db_utils(strategy, {
        "routes",
        "services",
        "plugins",
        "workspaces",
      }, {
        "correlation-id"
      })

      mock = http_mock.new(MOCK_PORT)
      mock:start()

      do
        --local ws_a = bp.workspaces:insert({name = "default"})
        -- setup workspace ws_a [[
        local mock_servce_a = bp.services:insert{
          host = 'localhost',
          port = MOCK_PORT,
        }

        bp.routes:insert{
          paths = { "/ws_a" },
          service = mock_servce_a
        }

        bp.plugins:insert{
          name = "correlation-id",
          config = {
            header_name = "Kong-Request-ID",
            generator =  "uuid",
            echo_downstream = true,
          },
        }
        -- ]]

      end

      do
        local ws_b = bp.workspaces:insert({ name = "ws_b" })
        -- setup workspace ws_b with no plugins [[
        local mock_service_b = bp.services:insert_ws({
          host = 'localhost',
          port = MOCK_PORT,
        }, ws_b)

        bp.routes:insert_ws({
          paths = { "/ws_b" },
          service = mock_service_b
        }, ws_b)
        -- ]]

      end

      assert(helpers.start_kong({
        database   = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }))
      proxy_client = helpers.proxy_client()
    end)

    lazy_teardown(function()
      helpers.stop_kong(nil, true)
      mock:stop()
    end)

    it("Doesn't trigger default workspace's plugin", function()
      local res = assert(proxy_client:send {
        method = "GET",
        path = "/ws_b/request",
      })

      assert.res_status(200, res)

      assert.is_nil(res.headers["Kong-Request-ID"]) -- does not trigger default workspace's plugin
    end)
  end)
end
