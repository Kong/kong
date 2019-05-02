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
          hosts     = { "retries.com" },
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
            host  = "retries.com"
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
          host     = "now.this.does.not",
          path     = "/exist",
          port     = 80,
          protocol = "http"
        }

        bp.routes:insert {
          hosts     = { "retries.com" },
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
            host  = "retries.com"
          }
        }
        assert.response(r).has.status(503)
      end)
    end)
  end)
end
