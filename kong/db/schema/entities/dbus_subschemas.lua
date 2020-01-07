local typedefs = require "kong.db.schema.typedefs"

local webhook_schema = {
  name = "webhook-custom",
  fields = {
    { config = {
      type = "record",
      required = true,
      fields = {
        { url = typedefs.url { required = true } },
        { method = typedefs.http_method { default = "GET" } },
        -- payload as a data map of string:string ideally we allow here any
        -- data structure, but I think that's not allowed
        { payload = { type = "map",
                      keys = { type = "string" },
                      values = { type = "string" },
                      required = false } },
        -- run resty templates on payload values
        { payload_format = { type = "boolean", default = true } },
        -- raw body
        { body = { type = "string", required = false, len_min = 0} },
        -- run body as a resty template
        { body_format = { type = "boolean", default = true} },
        { headers = { type = "map",
                      keys = { type = "string" },
                      values = { type = "string" },
                      default = {} } },
        -- run resty template on header values
        { headers_format = { type = "boolean", default = false } },
        -- sign body with secret
        { secret = { type = "string", required = false } },
      },
    } }
  },
}

local simple_webhook_schema = {
  name = "webhook",
  fields = {
    { config = {
      type = "record",
      required = true,
      fields = {
        { url = typedefs.url { required = true } },
        { headers = { type = "map",
                      keys = { type = "string" },
                      values = { type = "string" },
                      default = {} } },
        -- sign body with secret
        { secret = { type = "string", required = false } },
      },
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
  webhook = simple_webhook_schema,
  ["webhook-custom"] = webhook_schema,
  log = log_schema,
  slack = slack_schema,
  lambda = lambda_schema,
}
