-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local build_compound_key = require("kong.runloop.plugins_iterator").build_compound_key

describe("Testing build_compound_key function", function()
  it("Should create a compound key with all three IDs", function()
    local result = build_compound_key("route1", "service1", "consumer1")
    assert.are.equal("route1:service1:consumer1:", result)
  end)

  it("Should create a compound key with only route_id and service_id", function()
    local result = build_compound_key("route1", "service1", nil)
    assert.are.equal("route1:service1::", result)
  end)

  it("Should create a compound key with only route_id and consumer_id", function()
    local result = build_compound_key("route1", nil, "consumer1")
    assert.are.equal("route1::consumer1:", result)
  end)

  it("Should create a compound key with only service_id and consumer_id", function()
    local result = build_compound_key(nil, "service1", "consumer1")
    assert.are.equal(":service1:consumer1:", result)
  end)

  it("Should create a compound key with only route_id", function()
    local result = build_compound_key("route1", nil, nil)
    assert.are.equal("route1:::", result)
  end)

  it("Should create a compound key with only service_id", function()
    local result = build_compound_key(nil, "service1", nil)
    assert.are.equal(":service1::", result)
  end)

  it("Should create a compound key with only consumer_id", function()
    local result = build_compound_key(nil, nil, "consumer1")
    assert.are.equal("::consumer1:", result)
  end)

  it("Should create an empty compound key when all parameters are nil", function()
    local result = build_compound_key(nil, nil, nil)
    assert.are.equal(":::", result)
  end)
end)
