local helpers = require "spec.helpers"
local cjson   = require "cjson"
local FILE_LOG_PATH = os.tmpname()


local function find_in_file(f, pat)
  local line = f:read("*l")

  while line do
    if line:match(pat) then
      return true
    end

    line = f:read("*l")
  end

  return nil, "the pattern '" .. pat .. "' could not be found " ..
         "in the correct order in the log file"
end


describe("PDK: kong.log", function()
  local proxy_client
  local bp, db

  before_each(function()
    bp, db = helpers.get_db_utils(nil, {
      "routes",
      "services",
      "plugins",
    }, {
      "logger",
      "logger-last"
    })
  end)

  after_each(function()
    if proxy_client then
      proxy_client:close()
    end

    helpers.stop_kong()

    assert(db:truncate("routes"))
    assert(db:truncate("services"))
    db:truncate("plugins")
  end)

  it("namespaces the logs with the plugin name inside a plugin", function()
    local service = bp.services:insert({
      protocol = helpers.mock_upstream_ssl_protocol,
      host     = helpers.mock_upstream_ssl_host,
      port     = helpers.mock_upstream_ssl_port,
    })
    bp.routes:insert({
      service = service,
      protocols = { "https" },
      hosts = { "logger-plugin.test" }
    })

    bp.plugins:insert({
      name = "logger",
    })

    bp.plugins:insert({
      name = "logger-last",
    })

    assert(helpers.start_kong({
      plugins = "bundled,logger,logger-last",
      nginx_conf     = "spec/fixtures/custom_nginx.template",
    }))

    proxy_client = helpers.proxy_ssl_client()

    -- Do two requests
    for i = 1, 2 do
      local res = proxy_client:get("/request", {
        headers = { Host = "logger-plugin.test" }
      })
      assert.status(200, res)
    end

    -- wait for the second log phase to finish, otherwise it might not appear
    -- in the logs when executing this
    helpers.wait_until(function()
      local pl_file = require "pl.file"

      local cfg = helpers.test_conf
      local logs = pl_file.read(cfg.prefix .. "/" .. cfg.proxy_error_log)
      local _, count = logs:gsub("%[logger%-last%] log phase", "")

      return count == 2
    end, 10)

    local phrases = {
      "%[logger%] init_worker phase",    "%[logger%-last%] init_worker phase",
      "%[logger%] configure phase",      "%[logger%-last%] configure phase",

      "%[logger%] certificate phase",    "%[logger%-last%] certificate phase",

      "%[logger%] rewrite phase",        "%[logger%-last%] rewrite phase",
      "%[logger%] access phase",         "%[logger%-last%] access phase",
      "%[logger%] header_filter phase",  "%[logger%-last%] header_filter phase",
      "%[logger%] body_filter phase",    "%[logger%-last%] body_filter phase",
      "%[logger%] log phase",            "%[logger%-last%] log phase",

      "%[logger%] rewrite phase",        "%[logger%-last%] rewrite phase",
      "%[logger%] access phase",         "%[logger%-last%] access phase",
      "%[logger%] header_filter phase",  "%[logger%-last%] header_filter phase",
      "%[logger%] body_filter phase",    "%[logger%-last%] body_filter phase",
      "%[logger%] log phase",            "%[logger%-last%] log phase",
    }

    -- test that the phrases are logged twice on the specific order
    -- in which they are listed above
    local cfg = helpers.test_conf
    local f = assert(io.open(cfg.prefix .. "/" .. cfg.proxy_error_log, "r"))

    for j = 1, #phrases do
      assert(find_in_file(f, phrases[j]))
    end

    f:close()
  end)
end)

for _, strategy in helpers.each_strategy() do
  describe("PDK: make sure kong.log.serialize() will not modify ctx which's lifecycle " ..
           "is across request [#" .. strategy .. "]", function()
    describe("ctx.authenticated_consumer", function()
      local proxy_client
      local bp

      lazy_setup(function()
        bp, _ = helpers.get_db_utils(strategy, {
          "routes",
          "services",
          "plugins",
          "consumers",
          "acls",
          "keyauth_credentials",
        })

        local consumer = bp.consumers:insert( {
          username = "foo",
        })

        bp.keyauth_credentials:insert {
          key      = "test",
          consumer = { id = consumer.id },
        }

        bp.acls:insert {
          group    = "allowed",
          consumer = consumer,
        }

        local route1 = bp.routes:insert {
          paths = { "/status/200" },
        }

        bp.plugins:insert {
          name = "acl",
          route = { id = route1.id },
          config = {
            allow = { "allowed" },
          },
        }

        bp.plugins:insert {
          name     = "key-auth",
          route = { id = route1.id },
        }

        bp.plugins:insert {
          name     = "file-log",
          route   = { id = route1.id },
          config   = {
            path   = FILE_LOG_PATH,
            reopen = false,
            custom_fields_by_lua = {
              ["consumer.id"] = "return nil",
            },
          },
          protocols = {
            "http"
          },
        }

        assert(helpers.start_kong({
          plugins    = "bundled",
          database   = strategy,
          nginx_conf = "spec/fixtures/custom_nginx.template",
          db_cache_warmup_entities = "keyauth_credentials,consumers,acls",
          nginx_worker_processes = 1,
        }))
      end)

      before_each(function()
        proxy_client = helpers.proxy_client()
      end)

      after_each(function ()
        proxy_client:close()
      end)

      lazy_teardown(function()
        helpers.stop_kong()
      end)

      it("use the deep copy of Consumer object", function()
        for i = 1, 3 do
          local res = proxy_client:send {
            method  = "GET",
            path    = "/status/200",
            headers = {
              ["apikey"] = "test",
            }
          }
          assert.res_status(200, res)
        end
      end)
    end)

    describe("ctx.service", function()
      local proxy_client
      local bp

      lazy_setup(function()
        bp, _ = helpers.get_db_utils(strategy, {
          "routes",
          "services",
          "plugins",
        },{
          "error-handler-log",
        })

        local service = bp.services:insert {
          name = "example",
          host = helpers.mock_upstream_host,
          port = helpers.mock_upstream_port,
        }

        local route1 = bp.routes:insert {
          paths = { "/status/200" },
          service   = service,
        }

        bp.plugins:insert {
          name = "error-handler-log",
          config = {},
        }

        bp.plugins:insert {
          name     = "file-log",
          route   = { id = route1.id },
          config   = {
            path   = FILE_LOG_PATH,
            reopen = false,
            custom_fields_by_lua = {
              ["service.name"] = "return nil",
            },
          },
          protocols = {
            "http"
          },
        }

        assert(helpers.start_kong({
          plugins    = "bundled, error-handler-log",
          database   = strategy,
          nginx_conf = "spec/fixtures/custom_nginx.template",
          nginx_worker_processes = 1,
        }))
      end)

      before_each(function()
        proxy_client = helpers.proxy_client()
      end)

      after_each(function ()
        proxy_client:close()
      end)

      lazy_teardown(function()
        helpers.stop_kong()
      end)

      it("use the deep copy of Service object", function()
        for i = 1, 3 do
          local res = proxy_client:send {
            method  = "GET",
            path    = "/status/200",
          }
          assert.res_status(200, res)

          local service_matched_header = res.headers["Log-Plugin-Service-Matched"]
          assert.equal(service_matched_header, "example")
        end
      end)
    end)

    describe("ctx.route", function()
      local proxy_client
      local bp

      lazy_setup(function()
        bp, _ = helpers.get_db_utils(strategy, {
          "routes",
          "services",
          "plugins",
        })

        local service = bp.services:insert {
          host = helpers.mock_upstream_host,
          port = helpers.mock_upstream_port,
        }

        local route1 = bp.routes:insert {
          name = "route1",
          paths = { "/status/200" },
          service   = service,
        }

        assert(bp.plugins:insert {
          name = "request-termination",
          route = { id = route1.id },
          config = {
            status_code = 418,
            message = "No coffee for you. I'm a teapot.",
            echo = true,
          },
        })

        bp.plugins:insert {
          name     = "file-log",
          route   = { id = route1.id },
          config   = {
            path   = FILE_LOG_PATH,
            reopen = false,
            custom_fields_by_lua = {
              ["route.name"] = "return nil",
            },
          },
          protocols = {
            "http"
          },
        }

        assert(helpers.start_kong({
          plugins    = "bundled, error-handler-log",
          database   = strategy,
          nginx_conf = "spec/fixtures/custom_nginx.template",
          nginx_worker_processes = 1,
        }))
      end)

      before_each(function()
        proxy_client = helpers.proxy_client()
      end)

      after_each(function ()
        proxy_client:close()
      end)

      lazy_teardown(function()
        helpers.stop_kong()
      end)

      it("use the deep copy of Route object", function()
        for i = 1, 3 do
          local res = proxy_client:send {
            method  = "GET",
            path    = "/status/200",
          }

          local body = assert.res_status(418, res)
          local json = cjson.decode(body)
          assert.equal(json["matched_route"]["name"], "route1")
        end
      end)
    end)

    describe("in stream subsystem# ctx.authenticated_consumer", function()
      local proxy_client
      local bp

      local MESSAGE = "echo, ping, pong. echo, ping, pong. echo, ping, pong.\n"
      lazy_setup(function()
        bp, _ = helpers.get_db_utils(strategy, {
          "routes",
          "services",
          "plugins",
        })

        local service = assert(bp.services:insert {
          host     = helpers.mock_upstream_host,
          port     = helpers.mock_upstream_stream_port,
          protocol = "tcp",
        })

        local route1 = bp.routes:insert({
          destinations = {
            { port = 19000 },
          },
          protocols = {
            "tcp",
          },
          service = service,
        })

        bp.plugins:insert {
          name     = "file-log",
          route = { id = route1.id },
          config   = {
            path   = FILE_LOG_PATH,
            reopen = false,
            custom_fields_by_lua = {
              ["service.port"] = "return nil",
              ["service.host"] = "return nil",
            },
          },
          protocols = {
            "tcp"
          },
        }

        assert(helpers.start_kong({
          plugins    = "bundled, error-handler-log",
          database   = strategy,
          nginx_conf = "spec/fixtures/custom_nginx.template",
          nginx_worker_processes = 1,
          stream_listen = helpers.get_proxy_ip(false) .. ":19000",
          proxy_stream_error_log = "logs/error.log",
        }))
      end)

      before_each(function()
        proxy_client = helpers.proxy_client()
      end)

      after_each(function ()
        proxy_client:close()
      end)

      lazy_teardown(function()
        helpers.stop_kong()
      end)

      it("use the deep copy of Service object", function()
        for i = 1, 3 do
          local tcp_client = ngx.socket.tcp()
          assert(tcp_client:connect(helpers.get_proxy_ip(false), 19000))
          assert(tcp_client:send(MESSAGE))
          local body = assert(tcp_client:receive("*a"))
          assert.equal(MESSAGE, body)
          assert(tcp_client:close())
        end
      end)
    end)
  end)
end
