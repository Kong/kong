-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local PluginsIterator = require("kong.runloop.plugins_iterator")

describe("PluginsIterator.lookup_cfg", function()
	local combos = {
		["r:s:c:"] = "config1",
		["r::c:"] = "config2",
		[":s:c:"] = "config3",
		["r:s::"] = "config4",
		["::c:"] = "config5",
		["r:::"] = "config6",
		[":s::"] = "config7",
		[":::"] = "config8"
	}

	it("returns the correct configuration for a given route, service, consumer combination", function()
		local result = PluginsIterator.lookup_cfg(combos, "r", "s", "c")
		assert.equals(result, "config1")
	end)

	it("returns the correct configuration for a given route, consumer combination", function()
		local result = PluginsIterator.lookup_cfg(combos, "r", nil, "c")
		assert.equals(result, "config2")
	end)

	it("returns the correct configuration for a given service, consumer combination", function()
		local result = PluginsIterator.lookup_cfg(combos, nil, "s", "c")
		assert.equals(result, "config3")
	end)

	it("returns the correct configuration for a given route, service combination", function()
		local result = PluginsIterator.lookup_cfg(combos, "r", "s", nil)
		assert.equals(result, "config4")
	end)

	it("returns the correct configuration for a given consumer combination", function()
		local result = PluginsIterator.lookup_cfg(combos, nil, nil, "c")
		assert.equals(result, "config5")
	end)

	it("returns the correct configuration for a given route combination", function()
		local result = PluginsIterator.lookup_cfg(combos, "r", nil, nil)
		assert.equals(result, "config6")
	end)

	it("returns the correct configuration for a given service combination", function()
		local result = PluginsIterator.lookup_cfg(combos, nil, "s", nil)
		assert.equals(result, "config7")
	end)

	it("returns the correct configuration for the global configuration", function()
		local result = PluginsIterator.lookup_cfg(combos, nil, nil, nil)
		assert.equals(result, "config8")
	end)
end)
