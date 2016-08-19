local Errors = require "kong.dao.errors"

local REDIS = "redis"

return {
  fields = {
    second = { type = "number" },
    minute = { type = "number" },
    hour = { type = "number" },
    day = { type = "number" },
    month = { type = "number" },
    year = { type = "number" },
    limit_by = { type = "string", enum = {"consumer", "credential", "ip"}, default = "consumer" },
    policy = { type = "string", enum = {"local", "cluster", REDIS}, default = "cluster" },
    fault_tolerant = { type = "boolean", default = true },
    redis_host = { type = "string" },
    redis_port = { type = "number", default = 6379 },
    redis_password = { type = "string" },
    redis_timeout = { type = "number", default = 2000 }
  },
  self_check = function(schema, plugin_t, dao, is_update)
    local ordered_periods = { "second", "minute", "hour", "day", "month", "year"}
    local has_value
    local invalid_order
    local invalid_value

    for i, v in ipairs(ordered_periods) do
      if plugin_t[v] then
        has_value = true
        if plugin_t[v] <=0 then
          invalid_value = "Value for "..v.." must be greater than zero"
        else
          for t = i, #ordered_periods do
            if plugin_t[ordered_periods[t]] and plugin_t[ordered_periods[t]] < plugin_t[v] then
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

    if plugin_t.policy == REDIS then
      if not plugin_t.redis_host then
        return false, Errors.schema "You need to specify a Redis host"
      elseif not plugin_t.redis_port then
        return false, Errors.schema "You need to specify a Redis port"
      elseif not plugin_t.redis_timeout then
        return false, Errors.schema "You need to specify a Redis timeout"
      end
    end

    return true
  end
}
