local typedefs = require "kong.db.schema.typedefs"
local redis_schema = require "kong.tools.redis.schema"
local deprecation = require "kong.deprecation"

local ORDERED_PERIODS = { "second", "minute", "hour", "day", "month", "year" }


local function validate_periods_order(limit)
  for i, lower_period in ipairs(ORDERED_PERIODS) do
    local v1 = limit[lower_period]
    if type(v1) == "number" then
      for j = i + 1, #ORDERED_PERIODS do
        local upper_period = ORDERED_PERIODS[j]
        local v2 = limit[upper_period]
        if type(v2) == "number" and v2 < v1 then
          return nil, string.format("the limit for %s(%.1f) cannot be lower than the limit for %s(%.1f)",
            upper_period, v2, lower_period, v1)
        end
      end
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
  policy = {
    description =
    "The rate-limiting policies to use for retrieving and incrementing the limits.",
    type = "string",
    default = "local",
    one_of = {
      "local",
      "redis",
    },
  }
else
  policy = {
    description =
    "The rate-limiting policies to use for retrieving and incrementing the limits.",
    type = "string",
    default = "local",
    one_of = {
      "local",
      "cluster",
      "redis",
    },
  }
end


return {
  name = "response-ratelimiting",
  fields = {
    { protocols = typedefs.protocols_http },
    {
      config = {
        type = "record",
        fields = {
          {
            header_name = {
              description = "The name of the response header used to increment the counters.",
              type = "string",
              default = "x-kong-limit"
            },
          },
          {
            limit_by = {
              description =
              "The entity that will be used when aggregating the limits: `consumer`, `credential`, `ip`. If the `consumer` or the `credential` cannot be determined, the system will always fallback to `ip`.",
              type = "string",
              default = "consumer",
              one_of = { "consumer", "credential", "ip" },
            },
          },
          { policy = policy },
          {
            fault_tolerant = {
              description =
              "A boolean value that determines if the requests should be proxied even if Kong has troubles connecting a third-party datastore. If `true`, requests will be proxied anyway, effectively disabling the rate-limiting function until the datastore is working again. If `false`, then the clients will see `500` errors.",
              type = "boolean",
              required = true,
              default = true
            },
          },
          { redis = redis_schema.config_schema },
          {
            redis_host = typedefs.redis_host,
          },
          {
            redis_port = typedefs.port({
              default = 6379,
              description = "When using the `redis` policy, this property specifies the port of the Redis server."
            }),
          },
          {
            redis_password = {
              description =
              "When using the `redis` policy, this property specifies the password to connect to the Redis server.",
              type = "string",
              len_min = 0,
              referenceable = true
            },
          },
          {
            redis_username = {
              description =
              "When using the `redis` policy, this property specifies the username to connect to the Redis server when ACL authentication is desired.\nThis requires Redis v6.0.0+. The username **cannot** be set to `default`.",
              type = "string",
              referenceable = true
            },
          },
          {
            redis_ssl = {
              description =
              "When using the `redis` policy, this property specifies if SSL is used to connect to the Redis server.",
              type = "boolean",
              required = true,
              default = false,
            },
          },
          {
            redis_ssl_verify = {
              description =
              "When using the `redis` policy with `redis_ssl` set to `true`, this property specifies if the server SSL certificate is validated. Note that you need to configure the `lua_ssl_trusted_certificate` to specify the CA (or server) certificate used by your Redis server. You may also need to configure `lua_ssl_verify_depth` accordingly.",
              type = "boolean",
              required = true,
              default = false
            },
          },
          {
            redis_server_name = typedefs.redis_server_name
          },
          {
            redis_timeout = {
              description = "When using the `redis` policy, this property specifies the timeout in milliseconds of any command submitted to the Redis server.",
              type = "number",
              default = 2000
            },
          },
          {
            redis_database = {
              description = "When using the `redis` policy, this property specifies Redis database to use.",
              type = "number",
              default = 0
            },
          },
          {
            block_on_first_violation = {
              description =
              "A boolean value that determines if the requests should be blocked as soon as one limit is being exceeded. This will block requests that are supposed to consume other limits too.",
              type = "boolean",
              required = true,
              default = false
            },
          },
          {
            hide_client_headers = {
              description = "Optionally hide informative response headers.",
              type = "boolean",
              required = true,
              default = false
            },
          },
          {
            limits = {
              description = "A map that defines rate limits for the plugin.",
              type = "map",
              required = true,
              len_min = 1,
              keys = { type = "string" },
              values = {
                type = "record",
                required = true,
                fields = {
                  { second = { type = "number", gt = 0 }, },
                  { minute = { type = "number", gt = 0 }, },
                  { hour = { type = "number", gt = 0 }, },
                  { day = { type = "number", gt = 0 }, },
                  { month = { type = "number", gt = 0 }, },
                  { year = { type = "number", gt = 0 }, },
                },
                custom_validator = validate_periods_order,
                entity_checks = {
                  { at_least_one_of = ORDERED_PERIODS },
                },
              },
            },
          },
        },
      },
    },
  },
  entity_checks = {
    { conditional_at_least_one_of = {
      if_field = "config.policy", if_match = { eq = "redis" },
      then_at_least_one_of = { "config.redis.host", "config.redis_host" },
      then_err = "must set one of %s when 'policy' is 'redis'",
    } },
    { conditional_at_least_one_of = {
      if_field = "config.policy", if_match = { eq = "redis" },
      then_at_least_one_of = { "config.redis.port", "config.redis_port" },
      then_err = "must set one of %s when 'policy' is 'redis'",
    } },
    { conditional_at_least_one_of = {
      if_field = "config.policy", if_match = { eq = "redis" },
      then_at_least_one_of = { "config.redis.timeout", "config.redis_timeout" },
      then_err = "must set one of %s when 'policy' is 'redis'",
    } },
    { custom_entity_check = {
      field_sources = {
        "config.redis_host",
        "config.redis_port",
        "config.redis_password",
        "config.redis_username",
        "config.redis_ssl",
        "config.redis_ssl_verify",
        "config.redis_server_name",
        "config.redis_timeout",
        "config.redis_database"
      },
      fn = function(entity)
        if (entity.config.redis_host or ngx.null) ~= ngx.null then
          deprecation("response-ratelimiting: config.redis_host is deprecated, please use config.redis.host instead",
            { after = "4.0", })
        end
        if (entity.config.redis_port or ngx.null) ~= ngx.null and entity.config.redis_port ~= 6379 then
          deprecation("response-ratelimiting: config.redis_port is deprecated, please use config.redis.port instead",
            { after = "4.0", })
        end
        if (entity.config.redis_password or ngx.null) ~= ngx.null then
          deprecation("response-ratelimiting: config.redis_password is deprecated, please use config.redis.password instead",
            { after = "4.0", })
        end
        if (entity.config.redis_username or ngx.null) ~= ngx.null then
          deprecation("response-ratelimiting: config.redis_username is deprecated, please use config.redis.username instead",
            { after = "4.0", })
        end
        if (entity.config.redis_ssl or ngx.null) ~= ngx.null and entity.config.redis_ssl ~= false then
          deprecation("response-ratelimiting: config.redis_ssl is deprecated, please use config.redis.ssl instead",
            { after = "4.0", })
        end
        if (entity.config.redis_ssl_verify or ngx.null) ~= ngx.null and entity.config.redis_ssl_verify ~= false then
          deprecation("response-ratelimiting: config.redis_ssl_verify is deprecated, please use config.redis.ssl_verify instead",
            { after = "4.0", })
        end
        if (entity.config.redis_server_name or ngx.null) ~= ngx.null then
          deprecation("response-ratelimiting: config.redis_server_name is deprecated, please use config.redis.server_name instead",
            { after = "4.0", })
        end
        if (entity.config.redis_timeout or ngx.null) ~= ngx.null and entity.config.redis_timeout ~= 2000 then
          deprecation("response-ratelimiting: config.redis_timeout is deprecated, please use config.redis.timeout instead",
            { after = "4.0", })
        end
        if (entity.config.redis_database or ngx.null) ~= ngx.null and entity.config.redis_database ~= 0 then
          deprecation("response-ratelimiting: config.redis_database is deprecated, please use config.redis.database instead",
            { after = "4.0", })
        end

        return true
      end
    } }
  },
}
