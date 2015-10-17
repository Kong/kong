local route_helpers = require "kong.api.route_helpers"
local utils = require "kong.tools.utils"

describe("Route Helpers", function()
  
  it("should return the hostname", function()
    assert.truthy(utils.get_hostname())
  end)

  it("should return parse the nginx status", function()
    local status = "Active connections: 33 \nserver accepts handled requests\n 3 5 7 \nReading: 314 Writing: 1 Waiting: 2 \n"
    local res = route_helpers.parse_status(status)

    assert.are.equal(33, res.connections_active)
    assert.are.equal(3, res.connections_accepted)
    assert.are.equal(5, res.connections_handled)
    assert.are.equal(7, res.total_requests)
    assert.are.equal(314, res.connections_reading)
    assert.are.equal(1, res.connections_writing)
    assert.are.equal(2, res.connections_waiting)
  end)
end)
