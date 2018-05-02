local pl_config = require "pl.config"
local pl_stringio = require "pl.stringio"
local pl_path = require "pl.path"
local pl_file = require "pl.file"


local flags = {}
local values = {}
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
  flags = flags,
  values = values,
  is_enabled = is_enabled,
  get_feature_value = get_feature_value,
}
