local typedefs = require "kong.db.schema.typedefs"

local sandbox_helpers = require "kong.tools.sandbox_helpers"

local webhook_schema = {
  name = "webhook-custom",
  fields = {
    { config = {
      type = "record",
      required = true,
      fields = {
        { url = typedefs.url { required = true } },
        { method = typedefs.http_method { required = true } },
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
        { ssl_verify = { type = "boolean", default = false } },
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
        { ssl_verify = { type = "boolean", default = false } },
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


local functions_array = {
  type = "array",
  required = true,
  elements = { type = "string", custom_validator = sandbox_helpers.validate },
}


local lambda_schema = {
  name = "lambda",
  fields = {
    { config = {
      type = "record",
      required = true,
      fields = {
        { functions = functions_array },
      }
    } },
  },
}

return {
  webhook = simple_webhook_schema,
  ["webhook-custom"] = webhook_schema,
  log = log_schema,
  lambda = lambda_schema,
}
