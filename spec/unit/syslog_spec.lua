local syslog = require "kong.tools.syslog"
local Threads = require "llthreads2.ex"
local constants = require "kong.constants"
local utils = require "kong.tools.utils"
local stringy = require "stringy"

local function start_udp_server()
  local thread = Threads.new({
    function()
      local socket = require("socket")
      udp = socket.udp()
      udp:setsockname("*", 8889)
      data, ip, port = udp:receivefrom()
      return data
    end;
  })

  thread:start()
  return thread;
end

describe("Syslog", function()

  it("should log", function()
    local thread = start_udp_server() -- Starting the mock TCP server

    -- Override constants  
    constants.SYSLOG.ADDRESS = "127.0.0.1"
    constants.SYSLOG.PORT = 8889

    -- Make the request
    syslog.log({hello="world"})

    -- Getting back the TCP server input
    local ok, res = thread:join()
    assert.truthy(ok)
    assert.truthy(res)

    local PRIORITY = "<14>"

    assert.truthy(stringy.startswith(res, PRIORITY))
    res = string.sub(res, string.len(PRIORITY) + 1)

    local args = stringy.split(res, ";")
    assert.are.same(4, utils.table_size(args))

    local has_uname = false
    local has_cores = false
    local has_hostname = false
    local has_hello = false

    for _, v in ipairs(args) do
      local parts = stringy.split(v, "=")
      if parts[1] == "uname" and parts[2] and parts[2] ~= "" then
        has_uname = true
      elseif parts[1] == "cores" and parts[2] and parts[2] ~= "" then
        has_cores = true
      elseif parts[1] == "hostname" and parts[2] and parts[2] ~= "" then
        has_hostname = true
      elseif parts[1] == "hello" and parts[2] and parts[2] == "world" then
        has_hello = true
      end
    end

    assert.truthy(has_uname)
    assert.truthy(has_hostname)
    assert.truthy(has_cores)
    assert.truthy(has_hello)
  end)

end)