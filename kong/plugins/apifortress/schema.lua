-- The plugin schema

local IO = require "kong.tools.io"

local function validateKeys(value)
	return string.len(value) > 0
end

return {
  fields = {
   	apikey = { required = true, type = "string", func = validateKeys },
		secret = { required = true, type = "string", func = validateKeys },
		endpoint = {required = true, type = "string", func = validateKeys},
		projectId = {required = true , type = "number", func = validateKeys},
    threshold = {required = true, type = "number", func = validateKeys}
  }
}
