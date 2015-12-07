local cutils = require "kong.cli.utils"
local socket = require "socket"

describe("CLI Utils", function()
  pending("should check if a port is open", function()
    local PORT = 30000
    local server, success, err

    -- Check a currently closed port
    assert.truthy(cutils.is_port_bindable(PORT))

    -- Check an open port, with SO_REUSEADDR set
    server = socket.tcp()
    assert(server:setoption('reuseaddr', true))
    assert(server:bind("*", PORT))
    assert(server:listen())
    success, err = cutils.is_port_bindable(PORT)
    server:close()
    assert.truthy(success, err)

    -- Check an open port, without SO_REUSEADDR set
    server = socket.tcp()
    assert(server:bind("*", PORT))
    assert(server:listen())
    success, err = cutils.is_port_bindable(PORT)
    server:close()
    assert.falsy(success, err)

  end)
end)
