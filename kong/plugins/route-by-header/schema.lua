-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

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
    { config = {
      type = "record",
      fields = {
        { rules = { type = "array", default = {}, elements = rule }},
      }
    }}
  }
}
