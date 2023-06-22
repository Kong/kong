-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local PluginsIterator = require("kong.runloop.plugins_iterator")

describe("PluginsIterator.lookup_cfg", function()
  -- This is an ee-extension of spec/01-unit/28-plugins-iterator/lookup_cfg_spec.lua
  local combos = {
    ["r:s:c:"] = "config0",
    ["r:s::cg"] = "config1",
    [":s::cg"] = "config2",
    ["r:::cg"] = "config3",
    [":::cg"] = "config4",
  }

  it("returns the correct configuration for a given route, service, consumer combination", function()
    local result = PluginsIterator.lookup_cfg(combos, "r", "s", "c", nil)
    assert.equals(result, "config0")
  end)

  it("returns the correct configuration for a given route, service, consumer-group combination", function()
    local result = PluginsIterator.lookup_cfg(combos, "r", "s", nil, "cg")
    assert.equals(result, "config1")
  end)

  it("returns the correct configuration for a given service, consumer-group combination", function()
    local result = PluginsIterator.lookup_cfg(combos, nil, "s", nil, "cg")
    assert.equals(result, "config2")
  end)

  it("returns the correct configuration for a given route, consumer-group combination", function()
    local result = PluginsIterator.lookup_cfg(combos, "r", nil, nil, "cg")
    assert.equals(result, "config3")
  end)

  it("returns the correct configuration for a given consumer-group combination", function()
    local result = PluginsIterator.lookup_cfg(combos, nil, nil, nil, "cg")
    assert.equals(result, "config4")
  end)
end)
