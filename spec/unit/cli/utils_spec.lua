local cutils = require "kong.cli.utils"
local spec_helper = require "spec.spec_helpers"

describe("CLI Utils", function()
  it("should check if a port is open", function()
    local PORT, server, success = 30000, nil, nil
    
    -- Check a currently closed port
    assert.truthy(cutils.is_port_bindable(PORT))

    -- Check an open port, with SO_REUSEADDR set
    server = socket.tcp()
    assert(server:setoption('reuseaddr', true))
    assert(server:bind("*", PORT))
    assert(server:listen())
    success = cutils.is_port_bindable(PORT)
    server:close()
    assert.truthy(success)

    -- Check an open port, without SO_REUSEADDR set
    server = socket.tcp()
    assert(server:bind("*", PORT))
    assert(server:listen())
    success = cutils.is_port_bindable(PORT)
    server:close()
    assert.falsy(success)

  end)
end)
