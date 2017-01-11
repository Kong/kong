local helpers = require "spec.helpers"

local TCP_PORT = 35000

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
      assert(server:bind("*", port))
      assert(server:listen())
      while socket.gettime() < expire do
        local client, err = server:accept()
        socket.sleep(0.1)
        if client then
          client:close()  -- we're behaving bad, do nothing, just close
          tries = tries + 1
        elseif err ~= "timeout" then
          return nil, "error accepting tcp connection; "..tostring(err)
        end
      end
      server:close()
      return tries
    end
  }, port, duration)

  return thread:start(...)
end

describe("DNS", function()
  describe("retries", function()
    local retries = 3
    local client

    setup(function()
      assert(helpers.dao.apis:insert {
        name = "tests-retries",
        hosts = { "retries.com" },
        upstream_url = "http://127.0.0.1:"..TCP_PORT,
        retries = retries,
      })

      assert(helpers.start_kong())
      client = helpers.proxy_client()
    end)

    teardown(function()
      if client then client:close() end
      helpers.stop_kong()
    end)

    it("validates the number of retries", function()
      -- setup a bad server
      local thread = bad_tcp_server(TCP_PORT, 1)

      -- make a request to it
      local r = client:send {
        method = "GET",
        path = "/",
        headers = {
          host = "retries.com"
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
    local client

    setup(function()
      assert(helpers.dao.apis:insert {
        name = "tests-retries",
        hosts = { "retries.com" },
        upstream_url = "http://now.this.does.not/exist",
      })

      assert(helpers.start_kong())
      client = helpers.proxy_client()
    end)

    teardown(function()
      if client then client:close() end
      helpers.stop_kong()
    end)

    it("fails with 503", function()
      local r = client:send {
        method = "GET",
        path = "/",
        headers = {
          host = "retries.com"
        }
      }
      assert.response(r).has.status(503)
    end)
  end)
end)
