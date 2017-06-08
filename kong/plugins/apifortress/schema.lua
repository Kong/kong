-- The plugin schema

local function validateKeys(value)
  return #value > 0
end

local function validateThreshold(value)
  return value > 0
end

local function validateProjectId(value)
  return value > 0
end

return {
  fields = {
    apikey = { required = true, type = "string", func = validateKeys },
    secret = { required = true, type = "string", func = validateKeys },
    endpoint = {required = true, type = "string", func = validateKeys, default = "https://mastiff.apifortress.com/app/api/rest/v2/test/runAutomatch" },
    projectId = {required = true , type = "number", func = validateProjectId },
    threshold = {required = true, type = "number", func = validateThreshold, default=3 }
  }
}
