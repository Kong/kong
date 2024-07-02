local helpers = require "spec.helpers"

local TCP_PORT = 16945

local pack = function(...) return { n = select("#", ...), ... } end
local unpack = function(t) return unpack(t, 1, t.n) end

-- @param port the port to listen on
-- @param duration the duration for which to listen and accept connections (seconds)
local function bad_tcp_server(port, duration, ...)
  local threads = require "llthreads2.ex"
  local thread = threads.new({
    function(port, duration)
      local socket = require "socket"
      local expire = socket.gettime() + duration
      local server = assert(socket.tcp())
      local tries = 0
      server:settimeout(0.1)
      assert(server:setoption('reuseaddr', true))
      assert(server:bind("127.0.0.1", port))
      assert(server:listen())
      while socket.gettime() < expire do
        local client, err = server:accept()
        socket.sleep(0.1)
        if client then
          client:close()  -- we're behaving bad, do nothing, just close
          tries = tries + 1
        elseif err ~= "timeout" then
          return nil, "error accepting tcp connection; " .. tostring(err)
        end
      end
      server:close()
      return tries
    end
  }, port, duration)

  local result = pack(thread:start(...))
  ngx.sleep(0.2) -- wait for server to start
  return unpack(result)
end

for _, strategy in helpers.each_strategy() do
  describe("DNS [#" ..  strategy .. "]", function()
    describe("retries", function()
      local retries = 3
      local proxy_client

      lazy_setup(function()
        local bp = helpers.get_db_utils(strategy, {
          "routes",
          "services",
        })

        local service = bp.services:insert {
          name    = "tests-retries",
          port    = TCP_PORT,
          retries = retries,
        }

        bp.routes:insert {
          hosts     = { "retries.test" },
          service   = service
        }

        assert(helpers.start_kong{
          database = strategy,
        })

        proxy_client = helpers.proxy_client()
      end)

      lazy_teardown(function()
        if proxy_client then
          proxy_client:close()
        end

        helpers.stop_kong()
      end)

      it("validates the number of retries", function()
        -- setup a bad server
        local thread = bad_tcp_server(TCP_PORT, 1)

        -- make a request to it
        local r = proxy_client:send {
          method  = "GET",
          path    = "/",
          headers = {
            host  = "retries.test"
          }
        }
        assert.response(r).has.status(502)

        -- Getting back the TCP server count of the tries
        local ok, tries = thread:join()
        assert.True(ok)
        assert.equals(retries, tries-1 ) -- the -1 is because the initial one is not a retry.
      end)
    end)
    describe("upstream resolve failure", function()
      local proxy_client

      lazy_setup(function()
        local bp = helpers.get_db_utils(strategy, {
          "routes",
          "services",
        })

        local service = bp.services:insert {
          name     = "tests-retries",
          host     = "nowthisdoesnotexistatall.test",
          path     = "/exist",
          port     = 80,
          protocol = "http"
        }

        bp.routes:insert {
          hosts     = { "retries.test" },
          protocols = { "http" },
          service   = service
        }

        assert(helpers.start_kong({
          database = strategy,
        }))
        proxy_client = helpers.proxy_client()
      end)

      lazy_teardown(function()
        if proxy_client then
          proxy_client:close()
        end

        helpers.stop_kong()
      end)

      it("fails with 503", function()
        local r   = proxy_client:send {
          method  = "GET",
          path    = "/",
          headers = {
            host  = "retries.test"
          }
        }
        assert.response(r).has.status(503)
      end)
    end)

    -- lua-resty-dns is used for DNS query. It will create some UDP sockets
    -- during initialization. These sockets should be released after Query finish.
    -- The release is done by explicitly calling a destroy method that we patch.
    -- This test case is to check the UDP sockets are released after the DNS query
    -- is done.
    describe("udp sockets", function()
      local domain_name = "www.example.test"
      local address = "127.0.0.10"
      local proxy_client

      lazy_setup(function()
        local bp = helpers.get_db_utils(strategy, {
          "routes",
          "services",
        })

        local fixtures = {
          dns_mock = helpers.dns_mock.new()
        }
        fixtures.dns_mock:A({
          name = domain_name,
          address = address,
        })

        local service = bp.services:insert {
          name     = "foo",
          host     = domain_name,
        }

        bp.routes:insert {
          name = "foo",
          paths = { "/foo" },
          service = service,
        }

        assert(helpers.start_kong({ database = strategy }, nil, nil, fixtures))
      end)

      lazy_teardown(function()
        if proxy_client then
          proxy_client:close()
        end
        assert(helpers.stop_kong())
      end)

      it("release", function()
        proxy_client = helpers.proxy_client()
        proxy_client:send {
          method = "GET",
          path = "/foo",
          headers = {
            host = domain_name
          }
        }
        assert.logfile().has.line("serving '".. domain_name .. "' from mocks", true, 30)
        local ok, stderr, stdout = helpers.execute("netstat -n | grep 53 | grep udp | wc -l")
        assert.truthy(ok, stderr)
        assert.equals(0, assert(tonumber(stdout)))
      end)
    end)

    describe("run in stream subsystem", function()
      local domain_name = "www.example.test"
      local address = "127.0.0.1"

      local fixtures = {
        dns_mock = helpers.dns_mock.new()
      }
      fixtures.dns_mock:A({
        name = domain_name,
        address = address,
      })

      lazy_setup(function()
        local bp = helpers.get_db_utils(strategy, {
          "routes",
          "services",
        })

        local tcp_srv = bp.services:insert({
          name = "tcp",
          host = domain_name,
          port = helpers.mock_upstream_stream_port,
          protocol = "tcp",
        })

        bp.routes:insert {
          destinations = {
            { ip = "0.0.0.0/0", port = 19000 },
          },
          protocols = {
            "tcp",
          },
          service = tcp_srv,
        }

        assert(helpers.start_kong({
          database = strategy,
          nginx_conf = "spec/fixtures/custom_nginx.template",
          stream_listen = helpers.get_proxy_ip(false) .. ":19000",
          log_level = "info",
        }, nil, nil, fixtures))

      end)

      lazy_teardown(function()
        helpers.stop_kong()
      end)

      it("resolve domain name", function()
        local tcp = ngx.socket.tcp()
        assert(tcp:connect(helpers.get_proxy_ip(false), 19000))
        local MESSAGE = "echo, ping, pong. echo, ping, pong. echo, ping, pong.\n"
        assert(tcp:send(MESSAGE))
        local body = assert(tcp:receive("*a"))
        assert.equal(MESSAGE, body)
        tcp:close()
      end)
    end)
  end)
end
