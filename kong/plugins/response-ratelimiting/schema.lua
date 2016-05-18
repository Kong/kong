local Errors = require "kong.dao.errors"
local utils = require "kong.tools.utils"

local function check_ordered_limits(limit_value)
  local ordered_periods = { "second", "minute", "hour", "day", "month", "year"}
  local has_value
  local invalid_order
  local invalid_value

  for i, v in ipairs(ordered_periods) do
    if limit_value[v] then
      has_value = true
      if limit_value[v] <=0 then
        invalid_value = "Value for "..v.." must be greater than zero"
      else
        for t = i, #ordered_periods do
          if limit_value[ordered_periods[t]] and limit_value[ordered_periods[t]] < limit_value[v] then
            invalid_order = "The limit for "..ordered_periods[t].." cannot be lower than the limit for "..v
          end
        end
      end
    end
  end

  if not has_value then
    return false, Errors.schema "You need to set at least one limit: second, minute, hour, day, month, year"
  elseif invalid_value then
    return false, Errors.schema(invalid_value)
  elseif invalid_order then
    return false, Errors.schema(invalid_order)
  end

  return true
end

return {
  fields = {
    header_name = { type = "string", default = "x-kong-limit" },
    continue_on_error = { type = "boolean", default = false },
    block_on_first_violation = { type = "boolean", default = false},
    limits = { type = "table",
      schema = {
        flexible = true,
        fields = {
          second = { type = "number" },
          minute = { type = "number" },
          hour = { type = "number" },
          day = { type = "number" },
          month = { type = "number" },
          year = { type = "number" }
        }
      }
    }
  },
  self_check = function(schema, plugin_t, dao, is_update)
    if not plugin_t.limits or utils.table_size(plugin_t.limits) == 0 then
      return false, Errors.schema "You need to set at least one limit name"
    else
      for k,v in pairs(plugin_t.limits) do
        local ok, err = check_ordered_limits(v)
        if not ok then
          return false, err
        end
      end
    end

    return true
  end
}
