local pl_config = require "pl.config"
local pl_stringio = require "pl.stringio"
local pl_path = require "pl.path"
local pl_file = require "pl.file"


local FLAGS = {
  HMAC_AUTH_DISABLE_VALIDATE_REQUEST_BODY = "hmac_auth_disable_validate_request_body",
  KEY_AUTH_DISABLE_KEY_IN_BODY = "key_auth_disable_key_in_body",
  RATE_LIMITING_RESTRICT_REDIS_ONLY = "rate_limiting_restrict_redis_only",
  RESPONSE_RATELIMITING_RESTRICT_REDIS_ONLY = "response_ratelimiting_restrict_redis_only",
  RATE_LIMITING_ADVANCED_RESTRICT_REDIS_ONLY = "rate_limiting_advanced_restrict_redis_only",
  RATE_LIMITING_ADVANCED_ENABLE_WINDOW_SIZE_LIMIT = "rate_limiting_advanced_enable_window_size_limit",
  REQUEST_TRANSFORMER_ENABLE_LIMIT_BODY = "request_transformation_enable_limit_body",
  REQUEST_TRANSFORMER_ADVANCED_ENABLE_LIMIT_BODY = "request_transformation_advanced_enable_limit_body",
  RESPONSE_TRANSFORMER_ENABLE_LIMIT_BODY = "response_transformation_enable_limit_body",
  VITALS_READ_FROM_TSDB = "vitals_read_from_tsdb",
  INTERNAL_STATSD_PLUGIN = "internal_statsd_plugin",
}


local VALUES = {
  RATE_LIMITING_ADVANCED_WINDOW_SIZE_LIMIT = "rate_limiting_advanced_window_size_limit",
  REQUEST_TRANSFORMER_LIMIT_BODY_SIZE = "request_transformation_limit_body_size",
  REQUEST_TRANSFORMER_ADVANCED_LIMIT_BODY_SIZE = "request_transformation_advanced_limit_body_size",
  RESPONSE_TRANSFORMER_LIMIT_BODY_SIZE = "response_transformation_limit_body_size",
  REDIS_HOST = "redis_host",
  REDIS_PORT = "redis_port",
  REDIS_NAMESPACE = "redis_namespace",
  -- This config specifies the location to read Vitals data from and the protocol to follow
  -- example: vitals_tsdb_config={"type":"prometheus","host":"127.0.0.1","port":9090,"custom_filters"=[],"connection_timeout"=5000}
  VITALS_TSDB_CONFIG = "vitals_tsdb_config",
  -- example: internal_statsd_config={"host":"127.0.0.1","port":8125,"prefix":"kong","udp_packet_size":1000,"use_tcp":false}
  INTERNAL_STATSD_PLUGIN_CONFIG = "internal_statsd_plugin_config",
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
