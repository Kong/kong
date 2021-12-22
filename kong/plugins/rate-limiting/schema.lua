local typedefs = require "kong.db.schema.typedefs"


local ORDERED_PERIODS = { "second", "minute", "hour", "day", "month", "year"}


local function validate_periods_order(config)
  for i, lower_period in ipairs(ORDERED_PERIODS) do
    local v1 = config[lower_period]
    if type(v1) == "number" then
      for j = i + 1, #ORDERED_PERIODS do
        local upper_period = ORDERED_PERIODS[j]
        local v2 = config[upper_period]
        if type(v2) == "number" and v2 < v1 then
          return nil, string.format("The limit for %s(%.1f) cannot be lower than the limit for %s(%.1f)",
                                    upper_period, v2, lower_period, v1)
        end
      end
    end
  end

  return true
end

local function validate_periods_order_by_window_type(config)
  if config.window_type == "fixed" then
    return validate_periods_order(config)
  elseif config.window_type == "sliding" then
    return true
  end
end


local function is_dbless()
  local _, database, role = pcall(function()
    return kong.configuration.database,
           kong.configuration.role
  end)

  return database == "off" or role == "control_plane"
end


local policy
if is_dbless() then
  policy = {
    type = "string",
    default = "local",
    len_min = 0,
    one_of = {
      "local",
      "redis",
    },
  }

else
  policy = {
    type = "string",
    default = "cluster",
    len_min = 0,
    one_of = {
      "local",
      "cluster",
      "redis",
    },
  }
end


return {
  name = "rate-limiting",
  fields = {
    { protocols = typedefs.protocols_http },
    { config = {
        type = "record",
        fields = {
          { second = { type = "number", gt = 0 }, },
          { minute = { type = "number", gt = 0 }, },
          { hour = { type = "number", gt = 0 }, },
          { day = { type = "number", gt = 0 }, },
          { month = { type = "number", gt = 0 }, },
          { year = { type = "number", gt = 0 }, },
          { window_size = { type = "number", gt = 0 }, },
          { limit = { type = "number", gt = 0 }, },
          { window_type = {
            type = "string",
            default = "fixed",
            one_of = { "fixed", "sliding" },
          }, },
          { limit_by = {
              type = "string",
              default = "consumer",
              one_of = { "consumer", "credential", "ip", "service", "header", "path" },
          }, },
          { header_name = typedefs.header_name },
          { path = typedefs.path },
          { policy = policy },
          { fault_tolerant = { type = "boolean", required = true, default = true }, },
          { redis_host = typedefs.host },
          { redis_port = typedefs.port({ default = 6379 }), },
          { redis_password = { type = "string", len_min = 0, referenceable = true }, },
          { redis_username = { type = "string", referenceable = true }, },
          { redis_ssl = { type = "boolean", required = true, default = false, }, },
          { redis_ssl_verify = { type = "boolean", required = true, default = false }, },
          { redis_server_name = typedefs.sni },
          { redis_timeout = { type = "number", default = 2000, }, },
          { redis_database = { type = "integer", default = 0 }, },
          { hide_client_headers = { type = "boolean", required = true, default = false }, },
        },
        custom_validator = validate_periods_order_by_window_type,
      },
    },
  },
  entity_checks = {
    { conditional_at_least_one_of = { if_field = "config.window_type",
                                      if_match = { eq = "fixed" },
                                      then_at_least_one_of = { "config.second", "config.minute", "config.hour", "config.day", "config.month", "config.year" },
                                      then_err = "at least one of these fields must be non-empty: %s",
                                    }},
    { custom_entity_check = {
      field_sources = { "config" },
      fn = function(entity)
        local config = entity.config
        if config.window_type == "sliding" then
          if config.policy ~= "redis" then
            return nil, "On redis policy is supported when window_type == 'sliding'"
          end
        end
        return true
      end,
    } },
    { conditional = {
      if_field = "config.policy", if_match = { eq = "redis" },
      then_field = "config.redis_host", then_match = { required = true },
    } },
    { conditional = {
      if_field = "config.policy", if_match = { eq = "redis" },
      then_field = "config.redis_port", then_match = { required = true },
    } },
    { conditional = {
      if_field = "config.limit_by", if_match = { eq = "header" },
      then_field = "config.header_name", then_match = { required = true },
    } },
    { conditional = {
      if_field = "config.limit_by", if_match = { eq = "path" },
      then_field = "config.path", then_match = { required = true },
    } },
    { conditional = {
      if_field = "config.policy", if_match = { eq = "redis" },
      then_field = "config.redis_timeout", then_match = { required = true },
    } },
    { conditional = {
      if_field = "config.window_type", if_match = { eq = "sliding" },
      then_field = "config.limit", then_match = { required = true },
    } },
    { conditional = {
      if_field = "config.window_type", if_match = { eq = "sliding" },
      then_field = "config.window_size", then_match = { required = true },
    } },
  },
}
