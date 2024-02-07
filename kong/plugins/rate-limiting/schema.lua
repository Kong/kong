local typedefs = require "kong.db.schema.typedefs"


local SYNC_RATE_REALTIME = -1


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

  if config.policy ~= "redis" and config.sync_rate ~= SYNC_RATE_REALTIME then
    return nil, "sync_rate can only be used with the redis policy"
  end

  if config.policy == "redis" then
    if config.sync_rate ~= SYNC_RATE_REALTIME and config.sync_rate < 0.02 then
      return nil, "sync_rate must be greater than 0.02, or -1 to disable"
    end
  end

  return true
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
  policy = { description = "The rate-limiting policies to use for retrieving and incrementing the limits.", type = "string",
    default = "local",
    len_min = 0,
    one_of = {
      "local",
      "redis",
    },
  }

else
  policy = { description = "The rate-limiting policies to use for retrieving and incrementing the limits.", type = "string",
    default = "local",
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
          { second = { description = "The number of HTTP requests that can be made per second.", type = "number", gt = 0 }, },
          { minute = { description = "The number of HTTP requests that can be made per minute.", type = "number", gt = 0 }, },
          { hour = { description = "The number of HTTP requests that can be made per hour.", type = "number", gt = 0 }, },
          { day = { description = "The number of HTTP requests that can be made per day.", type = "number", gt = 0 }, },
          { month = { description = "The number of HTTP requests that can be made per month.", type = "number", gt = 0 }, },
          { year = { description = "The number of HTTP requests that can be made per year.", type = "number", gt = 0 }, },
          { limit_by = { description = "The entity that is used when aggregating the limits.", type = "string",
              default = "consumer",
              one_of = { "consumer", "credential", "ip", "service", "header", "path" },
          }, },
          { header_name = typedefs.header_name },
          { path = typedefs.path },
          { policy = policy },
          { fault_tolerant = { description = "A boolean value that determines if the requests should be proxied even if Kong has troubles connecting a third-party data store. If `true`, requests will be proxied anyway, effectively disabling the rate-limiting function until the data store is working again. If `false`, then the clients will see `500` errors.", type = "boolean", required = true, default = true }, },
          { redis_host = typedefs.host },
          { redis_port = typedefs.port({ default = 6379 }), },
          { redis_password = { description = "When using the `redis` policy, this property specifies the password to connect to the Redis server.", type = "string", len_min = 0, referenceable = true }, },
          { redis_username = { description = "When using the `redis` policy, this property specifies the username to connect to the Redis server when ACL authentication is desired.", type = "string", referenceable = true }, },
          { redis_ssl = { description = "When using the `redis` policy, this property specifies if SSL is used to connect to the Redis server.", type = "boolean", required = true, default = false, }, },
          { redis_ssl_verify = { description = "When using the `redis` policy with `redis_ssl` set to `true`, this property specifies it server SSL certificate is validated. Note that you need to configure the lua_ssl_trusted_certificate to specify the CA (or server) certificate used by your Redis server. You may also need to configure lua_ssl_verify_depth accordingly.", type = "boolean", required = true, default = false }, },
          { redis_server_name = typedefs.sni },
          { redis_timeout = { description = "When using the `redis` policy, this property specifies the timeout in milliseconds of any command submitted to the Redis server.", type = "number", default = 2000, }, },
          { redis_database = { description = "When using the `redis` policy, this property specifies the Redis database to use.", type = "integer", default = 0 }, },
          { hide_client_headers = { description = "Optionally hide informative response headers.", type = "boolean", required = true, default = false }, },
          { error_code = { description = "Set a custom error code to return when the rate limit is exceeded.", type = "number", default = 429, gt = 0 }, },
          { error_message = { description = "Set a custom error message to return when the rate limit is exceeded.", type = "string", default = "API rate limit exceeded" }, },
          { sync_rate = { description = "How often to sync counter data to the central data store. A value of -1 results in synchronous behavior.", type = "number", required = true, default = -1 }, },
        },
        custom_validator = validate_periods_order,
      },
    },
  },
  entity_checks = {
    { at_least_one_of = { "config.second", "config.minute", "config.hour", "config.day", "config.month", "config.year" } },
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
  },
}
