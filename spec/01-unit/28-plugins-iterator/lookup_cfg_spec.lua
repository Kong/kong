local PluginsIterator = require("kong.runloop.plugins_iterator")

describe("PluginsIterator.lookup_cfg", function()
	local combos = {
		["1:1:1"] = "config1",
		["1::1"] = "config2",
		[":1:1"] = "config3",
		["1:1:"] = "config4",
		["::1"] = "config5",
		["1::"] = "config6",
		[":1:"] = "config7",
		["::"] = "config8"
	}

	it("returns the correct configuration for a given route, service, consumer combination", function()
		local result = PluginsIterator.lookup_cfg(combos, "1", "1", "1")
		assert.equals(result, "config1")
	end)

	it("returns the correct configuration for a given route, consumer combination", function()
		local result = PluginsIterator.lookup_cfg(combos, "1", nil, "1")
		assert.equals(result, "config2")
	end)

	it("returns the correct configuration for a given service, consumer combination", function()
		local result = PluginsIterator.lookup_cfg(combos, nil, "1", "1")
		assert.equals(result, "config3")
	end)

	it("returns the correct configuration for a given route, service combination", function()
		local result = PluginsIterator.lookup_cfg(combos, "1", "1", nil)
		assert.equals(result, "config4")
	end)

	it("returns the correct configuration for a given consumer combination", function()
		local result = PluginsIterator.lookup_cfg(combos, nil, nil, "1")
		assert.equals(result, "config5")
	end)

	it("returns the correct configuration for a given route combination", function()
		local result = PluginsIterator.lookup_cfg(combos, "1", nil, nil)
		assert.equals(result, "config6")
	end)

	it("returns the correct configuration for a given service combination", function()
		local result = PluginsIterator.lookup_cfg(combos, nil, "1", nil)
		assert.equals(result, "config7")
	end)

	it("returns the correct configuration for the global configuration", function()
		local result = PluginsIterator.lookup_cfg(combos, nil, nil, nil)
		assert.equals(result, "config8")
	end)
end)
