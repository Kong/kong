local typedefs = require "kong.db.schema.typedefs"

local webhook_schema = {
  name = "webhook",
  fields = {
    { config = {
      type = "record",
      required = true,
      fields = {
        { url = typedefs.url, required = true },
        { method = typedefs.http_method { default = "GET" } },
        { payload = { type = "map",
                      keys = { type = "string" },
                      values = { type = "string" },
                      default = {} } },
        -- hardcoded payload or something formatted with event data
        { payload_format = { type = "boolean", default = true } },
        { headers = { type = "map",
                      keys = { type = "string" },
                      values = { type = "string" },
                      default = {} } },
        -- hardcoded headers or something formatted with event data
        { headers_format = { type = "boolean", default = false } },
      }
    } }
  },
}

local log_schema = {
  name = "log",
  fields = {
    { config = {
      type = "record",
      fields = {}
    } }
  }
}

local slack_schema = {
  name = "slack",
  fields = {
    { config = {
      type = "record",
      fields = {}
    } }
  }
}

local function validate_function(fun)
  local func1, err = loadstring(fun)
  if err then
    return false, "Error parsing function: " .. err
  end

  local success, func2 = pcall(func1)

  if not success or func2 == nil then
    -- the code IS the handler function
    return true
  end

  -- the code RETURNED the handler function
  if type(func2) == "function" then
    return true
  end

  -- the code returned something unknown
  return false, "Bad return value from function, expected function type, got "
                .. type(func2)
end


local functions_array = {
  type = "array",
  required = true,
  elements = { type = "string", custom_validator = validate_function }
}


local lambda_schema = {
  name = "lambda",
  fields = {
    { config = {
      type = "record",
      required = true,
      fields = {
        functions = functions_array,
      }
    } },
  },
}

return {
  webhook = webhook_schema,
  log = log_schema,
  slack = slack_schema,
  lambda = lambda_schema,
}
