local feature_flags = require "kong.enterprise_edition.feature_flags"


local FLAGS = feature_flags.FLAGS
local VALUES = feature_flags.VALUES


local overwrite_functions = {
  ["rate-limiting"] = function(schema)
    if not feature_flags.is_enabled(FLAGS.RATE_LIMITING_RESTRICT_REDIS_ONLY) then
      return true
    end

    local redis_host, err = feature_flags.get_feature_value(VALUES.REDIS_HOST)
    if err then
      return false, "feature value '" .. VALUES.REDIS_HOST ..
                    "' should be set when feature flag '" ..
                    FLAGS.RATE_LIMITING_RESTRICT_REDIS_ONLY .. "' is enabled"
    end

    local redis_port, err = feature_flags.get_feature_value(VALUES.REDIS_PORT)
    if err then
      return false, "feature value '" .. VALUES.REDIS_PORT ..
                    "' should be set when feature flag '" ..
                    FLAGS.RATE_LIMITING_RESTRICT_REDIS_ONLY .. "' is enabled"
    end

    schema.fields["policy"].default = nil
    schema.fields["policy"].overwrite = "redis"
    schema.fields["redis_host"].default = nil
    schema.fields["redis_host"].overwrite = redis_host
    schema.fields["redis_port"].default = nil
    schema.fields["redis_port"].overwrite = redis_port
    -- TODO(cloud): following is a hard-code for KongCloud
    -- Should these be made more flexible?
    schema.fields["redis_password"].default = nil
    schema.fields["redis_password"].overwrite = ngx.null
    schema.fields["redis_database"].default = nil
    schema.fields["redis_database"].overwrite = 0
    schema.fields["redis_timeout"].default = nil
    schema.fields["redis_timeout"].overwrite = 2000
    ngx.log(ngx.DEBUG, "rate-limiting restricted to redis strategy only")
    return true
  end,
  ["response-ratelimiting"] = function(schema)
    if not feature_flags.is_enabled(FLAGS.RESPONSE_RATELIMITING_RESTRICT_REDIS_ONLY) then
      return true
    end

    local redis_host, err = feature_flags.get_feature_value(VALUES.REDIS_HOST)
    if err then
      return false, "feature value '" .. VALUES.REDIS_HOST ..
                    "' should be set when feature flag '" ..
                    FLAGS.RESPONSE_RATELIMITING_RESTRICT_REDIS_ONLY .. "' is enabled"
    end

    local redis_port, err = feature_flags.get_feature_value(VALUES.REDIS_PORT)
    if err then
      return false, "feature value '" .. VALUES.REDIS_PORT ..
                    "' should be set when feature flag '" ..
                    FLAGS.RESPONSE_RATELIMITING_RESTRICT_REDIS_ONLY .. "' is enabled"
    end

    schema.fields["policy"].default = nil
    schema.fields["policy"].overwrite = "redis"
    schema.fields["redis_host"].default = nil
    schema.fields["redis_host"].overwrite = redis_host
    schema.fields["redis_port"].default = nil
    schema.fields["redis_port"].overwrite = redis_port
    -- TODO(cloud): following is a hard-code for KongCloud
    -- Should these be made more flexible?
    schema.fields["redis_password"].default = nil
    schema.fields["redis_password"].overwrite = ngx.null
    schema.fields["redis_database"].default = nil
    schema.fields["redis_database"].overwrite = 0
    schema.fields["redis_timeout"].default = nil
    schema.fields["redis_timeout"].overwrite = 2000
    ngx.log(ngx.DEBUG, "rate-limiting restricted to redis strategy only")
    return true
  end,
  ["rate-limiting-advanced"] = function(schema)
    if not feature_flags.is_enabled(FLAGS.RATE_LIMITING_ADVANCED_RESTRICT_REDIS_ONLY) then
      return true
    end

    local redis_host, err = feature_flags.get_feature_value(VALUES.REDIS_HOST)
    if err then
      return false, "feature value '" .. VALUES.REDIS_HOST ..
                    "' should be set when feature flag '" ..
                    FLAGS.RATE_LIMITING_ADVANCED_RESTRICT_REDIS_ONLY .. "' is enabled"
    end

    local redis_port, err = feature_flags.get_feature_value(VALUES.REDIS_PORT)
    if err then
      return false, "feature value '" .. VALUES.REDIS_PORT ..
                    "' should be set when feature flag '" ..
                    FLAGS.RATE_LIMITING_ADVANCED_RESTRICT_REDIS_ONLY .. "' is enabled"
    end

    local redis_namespace, err = feature_flags.get_feature_value(VALUES.REDIS_NAMESPACE)
    if err then
      return false, "feature value '" .. VALUES.REDIS_NAMESPACE ..
                    "' should be set when feature flag '" ..
                    FLAGS.RATE_LIMITING_RESTRICT_REDIS_ONLY .. "' is enabled"
    end

    schema.fields["strategy"].default = nil
    schema.fields["strategy"].required = nil
    schema.fields["strategy"].overwrite = "redis"
    schema.fields["namespace"].default = nil
    schema.fields["namespace"].overwrite = redis_namespace

    local redis_schema = schema.fields.redis.schema

    redis_schema.fields["host"].default = nil
    redis_schema.fields["host"].overwrite = redis_host
    redis_schema.fields["port"].default = nil
    redis_schema.fields["port"].overwrite = redis_port
    -- TODO(cloud): following is a hard-code for KongCloud
    -- Should these be made more flexible?
    redis_schema.fields["password"].default = nil
    redis_schema.fields["password"].overwrite = ngx.null
    redis_schema.fields["database"].default = nil
    redis_schema.fields["database"].overwrite = 0
    redis_schema.fields["timeout"].default = nil
    redis_schema.fields["timeout"].overwrite = 2000
    redis_schema.fields["sentinel_master"].default = nil
    redis_schema.fields["sentinel_master"].overwrite = ngx.null
    redis_schema.fields["sentinel_addresses"].default = nil
    redis_schema.fields["sentinel_addresses"].overwrite = ngx.null
    redis_schema.fields["sentinel_role"].default = nil
    redis_schema.fields["sentinel_role"].overwrite = ngx.null
    ngx.log(ngx.DEBUG, "rate-limiting restricted to redis strategy only")
    return true
  end,
}


local function add_overwrite(plugin_name, schema)
  if not plugin_name or not schema then
    return true
  end

  if not overwrite_functions[plugin_name] then
    return true
  end

  return overwrite_functions[plugin_name](schema)
end


return {
  add_overwrite = add_overwrite,
}

