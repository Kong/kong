local meta = require "kong.meta"
local utils = require "kong.tools.utils"
local syslog = require "kong.tools.syslog"
local stringy = require "stringy"
local constants = require "kong.constants"
local spec_helper = require "spec.spec_helpers"

local UDP_PORT = 8889

describe("Syslog", function()
  it("should log", function()
    local thread = spec_helper.start_udp_server(UDP_PORT) -- Starting the mock TCP server

    -- Override constants
    constants.SYSLOG.ADDRESS = "127.0.0.1"
    constants.SYSLOG.PORT = UDP_PORT

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
    assert.are.same(5, utils.table_size(args))

    local has_uname = false
    local has_cores = false
    local has_hostname = false
    local has_hello = false
    local has_version = false

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
      elseif parts[1] == "version" and parts[2] and parts[2] == meta._VERSION then
        has_version = true
      end
    end

    assert.truthy(has_uname)
    assert.truthy(has_hostname)
    assert.truthy(has_cores)
    assert.truthy(has_hello)
    assert.truthy(has_version)

    thread:join() -- wait til it exists
  end)
end)
