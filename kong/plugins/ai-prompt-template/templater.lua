local cjson = require "cjson.safe"

local _M = {}



--- sanitize table of parameters.
-- Any non-string values will be dropped.
-- @tparam table params the kv table to sanitize, if not a table will be replace with an empty table
-- @return the same table, with escaped values (without quotes)
local function sanitize_parameters(params)
  local result = {}

  if type(params) ~= "table" then
    return result
  end

  for k,v in pairs(params) do
    if type(v) == "string" then
      result[k] = cjson.encode(v):sub(2, -2)  -- remove quotes
    end
  end

  return result
end



do
  local GSUB_REPLACE_PATTERN = "{{([%w_]+)}}"

  function _M.render(template, properties)
    local sanitized_properties = sanitize_parameters(properties)

    local result = template.template:gsub(GSUB_REPLACE_PATTERN, sanitized_properties)

    -- find any missing variables
    local errors = {}
    local dup_check = {}
    for w in result:gmatch(GSUB_REPLACE_PATTERN) do
      if not dup_check[w] then
        dup_check[w] = true
        errors[#errors+1] = "[" .. w .. "]"
      end
    end

    local error_string
    if errors[1] then
      error_string = "missing template parameters: " .. table.concat(errors, ", ")
    end

    return result, error_string
  end
end


return _M
