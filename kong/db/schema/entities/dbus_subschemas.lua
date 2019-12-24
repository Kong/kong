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

return {
  webhook = webhook_schema,
  log = log_schema,
  slack = slack_schema,
}
