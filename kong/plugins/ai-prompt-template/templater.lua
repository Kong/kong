local cjson = require "cjson.safe"

local _M = {}



--- Sanitize properties object.
-- Incoming user-provided JSON object may contain any kind of data.
-- @tparam table params the kv table to sanitize
-- @treturn[1] table the escaped values (without quotes)
-- @treturn[2] nil
-- @treturn[2] string error message
local function sanitize_properties(params)
  local result = {}

  if type(params) ~= "table" then
    return nil, "properties must be an object"
  end

  for k,v in pairs(params) do
    if type(k) ~= "string" then
      return nil, "properties must be an object"
    end
    if type(v) == "string" then
      result[k] = cjson.encode(v):sub(2, -2)  -- remove quotes
    else
      return nil, "property values must be a string, got " .. type(v)
    end
  end

  return result
end



do
  local GSUB_REPLACE_PATTERN = "{{([%w_]+)}}"

  function _M.render(template, properties)
    local sanitized_properties, err = sanitize_properties(properties)
    if not sanitized_properties then
      return nil, err
    end

    local result = template.template:gsub(GSUB_REPLACE_PATTERN, sanitized_properties)

    -- find any missing variables
    local errors = {}
    local seen_before = {}
    for w in result:gmatch(GSUB_REPLACE_PATTERN) do
      if not seen_before[w] then
        seen_before[w] = true
        errors[#errors+1] = "[" .. w .. "]"
      end
    end

    if errors[1] then
      return nil, "missing template parameters: " .. table.concat(errors, ", ")
    end

    return result
  end
end


return _M
