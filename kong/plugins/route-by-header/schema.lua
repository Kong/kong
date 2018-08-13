local strip = require "kong.tools.utils".strip


local function check_for_value(rules)
  for _, rule in ipairs(rules) do
    if not rule.upstream_name or strip(rule.upstream_name) == "" or not rule.condition then
      return false, "each rules entry must have an 'upstream_name' and 'condition' defined"
    end

    if not next(rule.condition) then
      return false, "condition must have al-least one entry"
    end

  end
  return true
end


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
return {
  fields = {
    rules = {type = "table", default = {}, func = check_for_value},
  }
}

