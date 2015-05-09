local spec_helper = require "spec.spec_helpers"
local http_client = require "kong.tools.http_client"
local Threads = require "llthreads2.ex"

local STUB_GET_URL = spec_helper.STUB_GET_URL

local function start_tcp_server()
  local thread = Threads.new({
    function()
      local socket = require "socket"
      local server = assert(socket.bind("*", 7771))
      local client = server:accept()
      local line, err = client:receive()
      local message = "{\"ok\": true}"
      if not err then client:send("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: "..string.len(message).."\r\n\r\n"..message) end
      client:close()
      return line
    end;
  })

  thread:start()
  return thread;
end

describe("DNS", function()

  setup(function()
    spec_helper.prepare_db()
    spec_helper.start_kong()
  end)

  teardown(function()
    spec_helper.stop_kong()
    spec_helper.reset_db()
  end)

  describe("DNS", function()

    it("should work when calling local IP", function()
      local thread = start_tcp_server() -- Starting the mock TCP server
    
      local response, status = http_client.get(spec_helper.STUB_GET_URL, nil, { host = "dns1.com" })
      assert.are.equal(200, status)

      thread:join() -- Wait til it exists
    end)

    it("should work when calling local hostname", function()
      local thread = start_tcp_server() -- Starting the mock TCP server
    
      local response, status = http_client.get(spec_helper.STUB_GET_URL, nil, { host = "dns2.com" })
      assert.are.equal(200, status)

      thread:join() -- Wait til it exists
    end)

  end)

end)
