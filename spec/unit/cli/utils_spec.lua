local cutils = require "kong.cli.utils"
local spec_helper = require "spec.spec_helpers"

describe("CLI Utils", function()
  it("should check if a port is open", function()
    local PORT = 30000
    assert.falsy(cutils.is_port_open(PORT))
    spec_helper.start_tcp_server(PORT, true, true)
    os.execute("sleep 0.5") -- Wait for the server to start
    assert.truthy(cutils.is_port_open(PORT))
  end)
end)
