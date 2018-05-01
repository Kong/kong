local Errors = require "kong.dao.errors"

return {
	fields = {
		http_endpoint = { required = true, type = "url" },
		sample_ratio = { default = 0.001, type = "number" },
	},
	self_check = function(schema, plugin, dao, is_updating) -- luacheck: ignore 212
		if plugin.sample_ratio and (plugin.sample_ratio < 0 or plugin.sample_ratio > 1) then
			return false, Errors.schema "sample_ratio must be between 0 and 1"
		end
		return true
	end
}
