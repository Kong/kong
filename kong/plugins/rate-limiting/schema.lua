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
          { limit_by = {
              type = "string",
              default = "consumer",
              one_of = { "consumer", "credential", "ip", "service" },
          }, },
          { policy = {
              type = "string",
              default = "cluster",
              len_min = 0,
              one_of = { "local", "cluster", "redis" },
          }, },
          { fault_tolerant = { type = "boolean", default = true }, },
          { hide_client_headers = { type = "boolean", default = false }, },
          {
            redis = {
              type = "record",
              fields = {
                {sentinel_master = {type = "string", required = false}},
                {sentinel_addresses = {type = "array", elements = {type = "string"}, len_min = 1, required = false}},
                {host = typedefs.host {required = false}},
                {port = typedefs.port {required = false}},
                {keepalive_timeout = {type = "number", required = false, default = 60000}},
                {keepalive_poolsize = {type = "number", required = false, default = 100}},
                {read_timeout = {type = "number", required = true, gt = 0, default = 1000}},
                {connect_timeout = {type = "number", required = true, gt = 0, default = 1000}},
                {password = {type = "string", required = false}},
                {database = {type = "number", required = true, default = 0}}
              }
            }
          },
        },
        custom_validator = validate_periods_order,
      },
    },
  },
  entity_checks = {
    { at_least_one_of = { "config.second", "config.minute", "config.hour", "config.day", "config.month", "config.year" } },
    { conditional_at_least_one_of = {
      if_field = "config.policy", if_match = { eq = "redis" },
      then_at_least_one_of = {"config.redis.sentinel_addresses", "config.redis.host" },
    } },
    { conditional = {
      if_field = "config.policy", if_match = { eq = "redis" },
      then_field = "config.redis.read_timeout", then_match = { required = true },
    } },
    { conditional = {
      if_field = "config.policy", if_match = { eq = "redis" },
      then_field = "config.redis.connect_timeout", then_match = { required = true },
    } },
    { mutually_required = {"config.redis.host","config.redis.port" } },
  },
}
