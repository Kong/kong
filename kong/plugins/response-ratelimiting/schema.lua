local Errors = require "kong.dao.errors"

local REDIS = "redis"

local function check_ordered_limits(limit_value)
  local ordered_periods = { "second", "minute", "hour", "day", "month", "year"}
  local has_value
  local invalid_order
  local invalid_value

  for i, v in ipairs(ordered_periods) do
    if limit_value[v] then
      has_value = true
      if limit_value[v] <=0 then
        invalid_value = "Value for " .. v .. " must be greater than zero"
      else
        for t = i+1, #ordered_periods do
          if limit_value[ordered_periods[t]] and limit_value[ordered_periods[t]] < limit_value[v] then
            invalid_order = "The limit for " .. ordered_periods[t] .. " cannot be lower than the limit for " .. v
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
    limit_by = { type = "string", enum = {"consumer", "credential", "ip"}, default = "consumer" },
    policy = { type = "string", enum = {"local", "cluster", REDIS}, default = "cluster" },
    fault_tolerant = { type = "boolean", default = true },
    redis_host = { type = "string" },
    redis_port = { type = "number", default = 6379 },
    redis_password = { type = "string" },
    redis_timeout = { type = "number", default = 2000 },
    redis_database = { type = "number", default = 0 },
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
      },
      new_type = {
        type = "map",
        keys = {
          type = "string",
        },
        values = {
          type = "record",
          fields = {
            { second = { type = "number" } },
            { minute = { type = "number" } },
            { hour = { type = "number" } },
            { day = { type = "number" } },
            { month = { type = "number" } },
            { year = { type = "number" } }
          }
        },
        len_min = 1,
        default = {},
      },
    },
    hide_client_headers = { type = "boolean", default = false },
  },
  entity_checks = {
    { conditional = {
      if_field = "config.policy", if_match = { eq = "redis" },
      then_field = "config.redis_host", then_match = { required = true },
    } },
    { conditional = {
      if_field = "config.policy", if_match = { eq = "redis" },
      then_field = "config.redis_port", then_match = { required = true },
    } },
    { conditional = {
      if_field = "config.policy", if_match = { eq = "redis" },
      then_field = "config.redis_timeout", then_match = { required = true },
    } },
  },
  self_check = function(schema, plugin_t, dao, is_update)
    if not plugin_t.limits or (not next(plugin_t.limits)) then
      return false, Errors.schema "You need to set at least one limit name"
    else
      for k,v in pairs(plugin_t.limits) do
        local ok, err = check_ordered_limits(v)
        if not ok then
          return false, err
        end
      end
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
