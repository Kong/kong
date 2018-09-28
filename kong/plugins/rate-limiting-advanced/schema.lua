local Errors = require "kong.dao.errors"
local utils  = require "kong.tools.utils"
local redis  = require "kong.enterprise_edition.redis"
local errors = require "kong.dao.errors"

local function validate_rl(value)
  for i = 1, #value do
    local x = tonumber(value[i])

    if not x then
      return false, "size/limit values must be numbers"
    end
  end

  return true
end


local function check_shdict(name)
  if not ngx.shared[name] then
    return false, "missing shared dict '" .. name .. "'"
  end

  return true
end


return {
  fields = {
    identifier = {
      type = "string",
      enum = { "ip", "credential", "consumer" },
      required = true,
      default = "consumer",
    },
    window_size = {
      type = "array",
      required = true,
      func = validate_rl,
    },
    window_type = {
      type = "string",
      enum = { "fixed", "sliding" },
      default = "sliding",
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
      schema = redis.config_schema,
    },
    dictionary_name = {
      type = "string",
      required = true,
      default = "kong_rate_limiting_counters",
    },
    hide_client_headers = {
      type = "boolean",
      default = false,
    },
  },
  self_check = function(schema, plugin_t, dao, is_updating)
    if plugin_t.dictionary_name ~= nil then
      local ok, err = check_shdict(plugin_t.dictionary_name)
      if not ok then
        return false, errors.schema(err)
      end
    end

    -- empty semi-optional redis config, needs to be cluster strategy
    if plugin_t.strategy == "redis" then
      if not plugin_t.redis then
        return false, Errors.schema("No redis config provided")
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

    -- KongCloud start
    local ok, feature_flags = utils.load_module_if_exists("kong.enterprise_edition.feature_flags")
    if ok and feature_flags and feature_flags.is_enabled(feature_flags.FLAGS.RATE_LIMITING_ADVANCED_ENABLE_WINDOW_SIZE_LIMIT) then
      local max_window_size, err = feature_flags.get_feature_value(feature_flags.VALUES.RATE_LIMITING_ADVANCED_WINDOW_SIZE_LIMIT)
      if not err then
        max_window_size = tonumber(max_window_size)
        if max_window_size then
          for i = 1, #plugin_t.window_size do
            if tonumber(plugin_t.window_size[i]) > max_window_size then
              return false, Errors.schema("windown_size cannot be greater than "
                            .. max_window_size)
            end
          end
        end
      end
    end
    -- KongCloud end


    -- sort the window_size and limit arrays by limit
    -- first we create a temp table, each element of which is a pair of
    -- limit/window_size values. we then sort based on the limit element
    -- of this array of pairs. finally, we re-assign the plugin_t configuration
    -- elements directly based off the sorted temp table
    local t = {}
    for i, v in ipairs(plugin_t.limit) do
      t[i] = { plugin_t.limit[i], plugin_t.window_size[i] }
    end

    table.sort(t, function(a, b) return tonumber(a[1]) < tonumber(b[1]) end)

    for i = 1, #t do
      plugin_t.limit[i] = tonumber(t[i][1])
      plugin_t.window_size[i] = tonumber(t[i][2])
    end

    return true
  end,
}
