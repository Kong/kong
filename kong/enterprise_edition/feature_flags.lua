local pl_config = require "pl.config"
local pl_stringio = require "pl.stringio"
local pl_path = require "pl.path"
local pl_file = require "pl.file"


local FLAGS = {
  RATE_LIMITING_RESTRICT_REDIS_ONLY = "rate_limiting_restrict_redis_only",
  RESPONSE_RATELIMITING_RESTRICT_REDIS_ONLY = "response_ratelimiting_restrict_redis_only",
  RATE_LIMITING_ADVANCED_RESTRICT_REDIS_ONLY = "rate_limiting_advanced_restrict_redis_only",
  RESPONSE_TRANSFORMER_ENABLE_LIMIT_BODY = "response_transformation_enable_limit_body",
  VITALS_PROMETHEUS_ENABLE_CLUSTER_LEVEL = "vitals_prometheus_enable_cluster_level",
}


local VALUES = {
  RESPONSE_TRANSFORMER_LIMIT_BODY_SIZE = "response_transformation_limit_body_size",
  REDIS_HOST = "redis_host",
  REDIS_PORT = "redis_port",
  REDIS_NAMESPACE = "redis_namespace",
  VITALS_PROMETHEUS_AUTH_HEADER = "vitals_prometheus_auth_header",
  VITALS_PROMETHEUS_CUSTOM_FILTERS = "vitals_prometheus_custom_filters"
}


local loaded_conf = {}


local function init(feature_conf_path)
  if not feature_conf_path or not pl_path.exists(feature_conf_path) then
    return false, "feature_conf: no such file " .. feature_conf_path
  end
  local f, err = pl_file.read(feature_conf_path)
  if not f or err then
    return false, err
  end
  local s = pl_stringio.open(f)
  local config, err = pl_config.read(s, {
    smart = false,
    list_delim = "_blank_",
  })
  if err then
    return false, err
  end
  loaded_conf = config
  return true
end


-- Check if a feature is enabled or not, returns true if enabled
local function is_enabled(feature)
  return loaded_conf[feature] ~= nil and
    string.lower(loaded_conf[feature]) == "on"
end


-- Get value of a feature
local function get_feature_value(key)
  local value = loaded_conf[key]
  if not value then
    return nil, "key: '" .. key .. "' not found in feature conf file"
  end
  return value
end


return {
  init = init,
  FLAGS = FLAGS,
  VALUES = VALUES,
  is_enabled = is_enabled,
  get_feature_value = get_feature_value,
}
