-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local typedefs = require "kong.db.schema.typedefs"
local null = ngx.null

local function is_null_value(value)
  if value == null or value == nil then
    return true
  end

  return false
end

local function validate_steps(config)
  if not is_null_value(config.canary_by_header_name) or
                          config.consumer == "allow" or
                           config.consumer == "deny" or
                     not is_null_value(config.steps)
  then

    return true
  end

  return false, "config.steps must be a number greater than 1"
end

return {
  name = "canary",
  fields = {
    { consumer = typedefs.no_consumer },
    { consumer_group = typedefs.no_consumer_group },
    { protocols = typedefs.protocols_http },
    { config = {
        type = "record",
        shorthand_fields = {
          -- deprecated forms, to be removed in Kong 3.0
          { hash = {
            type = "string",
            description = "Hash algorithm to be used for canary release. `whitelist` is deprecated. Use `allow` instead `blacklist` is deprecated. Use `deny` instead.",
            func = function(value)
              if value == "whitelist" then
                value = "allow"
              elseif value == "blacklist" then
                value = "deny"
              end

              return { hash = value }
            end,
          }},
        },
        custom_validator = validate_steps,
        fields = {
          { start = { description = "Future time in seconds since epoch, when the canary release will start. Ignored when `percentage` is set, or when using `allow` or `deny` in `hash`.", type = "number",
          }},
          { hash = {
              description = "Hash algorithm to be used for canary release.\n\n* `consumer`: The hash will be based on the consumer.\n* `ip`: The hash will be based on the client IP address.\n* `none`: No hash will be applied.\n* `allow`: Allows the specified groups to access the canary release.\n* `deny`: Denies the specified groups from accessing the canary release.\n* `header`: The hash will be based on the specified header value.",
              type = "string",
              default = "consumer",
              one_of = { "consumer", "ip", "none", "allow", "deny", "header" },
          }},
          { hash_header = typedefs.header_name },
          { duration = {
              description = "The duration of the canary release in seconds.",
              type = "number",
              default = 60 * 60,
              gt = 0
          }},
          { steps = {
              description = "The number of steps for the canary release.",
              type = "number",
              default = 1000,
              gt = 1
          }},
          { percentage = {
              description = "The percentage of traffic to be routed to the canary release.",
              type = "number",
              between = { 0, 100 }
          }},
          { upstream_host = typedefs.host },
          { upstream_port = typedefs.port },
          { upstream_uri = {
              description = "The URI of the upstream server to be used for the canary release.",
              type = "string",
              len_min = 1
          }},
          { upstream_fallback = {
              description = "Specifies whether to fallback to the upstream server if the canary release fails.",
              type = "boolean",
              default = false,
              required = true
          }},
          { groups = {
              description = "The groups allowed to access the canary release.",
              type = "array",
              elements = { type = "string" }
          }},
          { canary_by_header_name =  typedefs.header_name },
        }
    }}
  },
  transformations = {
    {
      input = { "config" },
      on_write = function(config)
        -- if both start time and percentage is not set and hash mode is not
        -- allow/deny, then default the start time to ngx.time()
        -- if percentage is set, percentage fixed step will take precedence
        local start, percentage, duration, hash = config.start, config.percentage,
                                                  config.duration, config.hash
        if is_null_value(start) and is_null_value(percentage) then
          if not is_null_value(duration) and not is_null_value(hash)
            and hash ~= "allow" and hash ~= "deny" then
              config.start = ngx.time()
          end
        end

        return { config = config }
      end,
    }
  },
  entity_checks = {
    { at_least_one_of = { "config.upstream_uri", "config.upstream_host", "config.upstream_port" }},
    { conditional = {
        if_field = "config.hash", if_match = { eq = "header" },
        then_field = "config.hash_header", then_match = { required = true }
    }},
    { conditional = {
        if_field = "config.upstream_fallback", if_match = { eq = true },
        then_field = "config.upstream_host", then_match = { required = true }
    }},
  }
}