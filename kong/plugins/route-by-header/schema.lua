local typedefs = require "kong.db.schema.typedefs"

--[[
  config schema
  "config": {
    "rules": [
      {
        "upstream_name": "json.domian.com",
        "condition": {
          "header1": "value2",
          "header2": "some_value"
        }
      },
      {
        "upstream_name": "foo.domian.com",
        "condition": {
          "header1": "some_value",
          "header2": "some_value",
          "header3": "some_value"
        }
      }
    ]
  },
]]

local rule = {
  type = "record",
  fields = {
    { upstream_name = { type = "string", required = true } },
    { condition = {
      type = "map",
      required = true,
      len_min = 1,
      keys = { type = "string" },
      values = { type = "string" },
    }},
  }
}

return {
  name = "route-by-header",
  fields = {
    { run_on = typedefs.run_on_first },
    { config = {
      type = "record",
      fields = {
        { rules = { type = "array", default = {}, elements = rule }},
      }
    }}
  }
}
