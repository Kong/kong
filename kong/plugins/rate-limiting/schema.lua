local Errors = require "kong.dao.errors"
local utils  = require "kong.tools.utils"

local function validate_rl(value)
  for i = 1, #value do
    local x = tonumber(value[i])

    if not x then
      return false, "size/limit values must be numbers"
    end
  end

  return true
end

local function is_redis_sentinel(redis)
  local is_sentinel = redis.sentinel_master or
                      redis.sentinel_role or
                      redis.sentinel_addresses

  return is_sentinel and true or false
end

local redis_schema = {
  fields = {
    host = {
      type = "string",
    },
    port = {
      type = "number",
    },
    timeout = {
      type = "number",
    },
    password = {
      type = "string",
    },
    database = {
      type = "number",
    },
    sentinel_master = {
      type = "string",
    },
    sentinel_role = {
      type = "string",
      enum = { "master", "slave", "any" },
    },
    sentinel_addresses = {
      type = "array",
    },
  },
  self_check = function(schema, plugin_t, dao, is_updating)
    if is_redis_sentinel(plugin_t) then
      if not plugin_t.sentinel_master then
        return false,
               Errors.schema("You need to specify a Redis Sentinel master")
      end

      if not plugin_t.sentinel_role then
        return false,
               Errors.schema("You need to specify a Redis Sentinel role")
      end

      if not plugin_t.sentinel_addresses then
        return false,
               Errors.schema("You need to specify one or more " ..
               "Redis Sentinel addresses")

      else
        if plugin_t.host then
          return false,
                 Errors.schema("When Redis Sentinel is enabled you cannot " ..
                 "set a 'redis.host'")
        end

        if plugin_t.port then
          return false,
                 Errors.schema("When Redis Sentinel is enabled you cannot " ..
                 "set a 'redis.port'")
        end

        if #plugin_t.sentinel_addresses == 0 then
          return false,
                 Errors.schema("You need to specify one or more " ..
                 "Redis Sentinel addresses")
        end

        for _, address in ipairs(plugin_t.sentinel_addresses) do
          local parts = utils.split(address, ":")

          if not (#parts == 2 and tonumber(parts[2])) then
            return false,
                   Errors.schema("Invalid Redis Sentinel address: " .. address)
          end
        end
      end
    end
  end,
}

return {
  fields = {
    identifier = {
      type = "string",
      enum = { "ip", "credential", "consumer" },
      required = true,
      default = "ip",
    },
    window_size = {
      type = "array",
      required = true,
      func = validate_rl,
    },
    limit = {
      type = "array",
      required = true,
      func = validate_rl,
    },
    sync_rate = {
      type = "number",
      required = true,
    },
    namespace = {
      type = "string",
      required = true,
      default = utils.random_string,
    },
    strategy = {
      type = "string",
      enum = { "cluster", "redis", },
      required = true,
      default = "cluster",
    },
    redis = {
      type = "table",
      schema = redis_schema,
    },
  },
  self_check = function(schema, plugin_t, dao, is_updating)
    -- empty semi-optional redis config, needs to be cluster strategy
    if plugin_t.strategy == "redis" then
      if not plugin_t.redis then
        return false, Errors.schema("No redis config provided")
      end

      -- if sentinel is not used, we need to define host + port
      -- if sentinel IS used, we cannot define host or port (checked above)
      if not is_redis_sentinel(plugin_t.redis) then
        if not plugin_t.redis.host then
          return false, Errors.schema("Redis host must be provided")
        end

        if not plugin_t.redis.port then
          return false, Errors.schema("Redis port must be provided")
        end
      end

      if not plugin_t.redis.database then
        plugin_t.redis.database = 0
      end

      if not plugin_t.redis.timeout then
        plugin_t.redis.timeout = 2000
      end
    end

    -- on update we dont need to enforce re-defining window_size and limit
    -- e.g., skip the next checks if this is an update and the request body
    -- did not contain either the window_size or limit values. the reason for
    -- this is the check that is executing here looks at the request body, not
    -- the entity post-update. so to simplify PATCH requests we do not want to
    -- force the user to define window_size and limit when they don't need to
    -- (say, they are only updating sync_rate)
    --
    -- if this request is an update, and window_size and/or limit are being
    -- updated, then we do want to execute the manual checks on these entities.
    -- in such case the condition below evaluates to false, and we fall through
    -- to the next series of checks
    if is_updating and not plugin_t.window_size and not plugin_t.limit then
      return true
    end

    if not plugin_t.window_size or not plugin_t.limit then
      return false, Errors.schema(
                    "Both window_size and limit must be provided")
    end

    if #plugin_t.window_size ~= #plugin_t.limit then
      return false, Errors.schema(
                    "You must provide the same number of windows and limits")
    end

    return true
  end,
}
