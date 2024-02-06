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
        shorthand_fields = {
          -- TODO: deprecated forms, to be removed in Kong 4.0
          { redis_host = {
            type = "string",
            translate_backwards = {'redis', 'host'},
            func = function(value)
              deprecation("response-ratelimiting: config.redis_host is deprecated, please use config.redis.host instead",
                { after = "4.0", })
              return { redis = { host = value } }
            end
          } },
          { redis_port = {
            type = "integer",
            translate_backwards = {'redis', 'port'},
            func = function(value)
              deprecation("response-ratelimiting: config.redis_port is deprecated, please use config.redis.port instead",
                { after = "4.0", })
              return { redis = { port = value } }
            end
          } },
          { redis_password = {
            type = "string",
            len_min = 0,
            translate_backwards = {'redis', 'password'},
            func = function(value)
              deprecation("response-ratelimiting: config.redis_password is deprecated, please use config.redis.password instead",
                { after = "4.0", })
              return { redis = { password = value } }
            end
          } },
          { redis_username = {
            type = "string",
            translate_backwards = {'redis', 'username'},
            func = function(value)
              deprecation("response-ratelimiting: config.redis_username is deprecated, please use config.redis.username instead",
                { after = "4.0", })
              return { redis = { username = value } }
            end
          } },
          { redis_ssl = {
            type = "boolean",
            translate_backwards = {'redis', 'ssl'},
            func = function(value)
              deprecation("response-ratelimiting: config.redis_ssl is deprecated, please use config.redis.ssl instead",
                { after = "4.0", })
              return { redis = { ssl = value } }
            end
          } },
          { redis_ssl_verify = {
            type = "boolean",
            translate_backwards = {'redis', 'ssl_verify'},
            func = function(value)
              deprecation("response-ratelimiting: config.redis_ssl_verify is deprecated, please use config.redis.ssl_verify instead",
                { after = "4.0", })
              return { redis = { ssl_verify = value } }
            end
          } },
          { redis_server_name = {
            type = "string",
            translate_backwards = {'redis', 'server_name'},
            func = function(value)
              deprecation("response-ratelimiting: config.redis_server_name is deprecated, please use config.redis.server_name instead",
                { after = "4.0", })
              return { redis = { server_name = value } }
            end
          } },
          { redis_timeout = {
            type = "integer",
            translate_backwards = {'redis', 'timeout'},
            func = function(value)
              deprecation("response-ratelimiting: config.redis_timeout is deprecated, please use config.redis.timeout instead",
                { after = "4.0", })
              return { redis = { timeout = value } }
            end
          } },
          { redis_database = {
            type = "integer",
            translate_backwards = {'redis', 'database'},
            func = function(value)
              deprecation("response-ratelimiting: config.redis_database is deprecated, please use config.redis.database instead",
                { after = "4.0", })
              return { redis = { database = value } }
            end
          } },
        },
      },
    },
  },
  entity_checks = {
    { conditional = {
      if_field = "config.policy", if_match = { eq = "redis" },
      then_field = "config.redis.host", then_match = { required = true },
    } },
    { conditional = {
      if_field = "config.policy", if_match = { eq = "redis" },
      then_field = "config.redis.port", then_match = { required = true },
    } },
    { conditional = {
      if_field = "config.policy", if_match = { eq = "redis" },
      then_field = "config.redis.timeout", then_match = { required = true },
    } },
  },
}
