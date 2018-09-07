local enums       = require "kong.enterprise_edition.dao.enums"
local ee_jwt      = require "kong.enterprise_edition.jwt"
local api_helpers = require "lapis.application"
local singletons  = require "kong.singletons"
local time        = ngx.time
local floor       = math.floor


local SERVICE_ID = "00000000-0000-0000-0000-000000000000"


local _M = {}


_M.portal_plugins = {}


_M.find_plugin = function(name)
  if _M.portal_plugins[name] then
    return _M.portal_plugins[name]
  end

  for _, plugin in ipairs(singletons.loaded_plugins) do
    if plugin.name == name then
      _M.portal_plugins[name] = plugin
      return plugin
    end
  end

  return nil, "plugin not found"
end


_M.pluralize_time = function(val, unit)
  if val ~= 1 then
    return val .. " " .. unit .. "s"
  end

  return val .. " " .. unit
end


_M.append_time = function(val, unit, ret_string, append_zero)
  if val > 0 or append_zero then
    if ret_string == "" then
      return _M.pluralize_time(val, unit)
    end

    return ret_string .. " " .. _M.pluralize_time(val, unit)
  end

  return ret_string
end


_M.humanize_timestamp = function(seconds, append_zero)
  local day = floor(seconds/86400)
  local hour = floor((seconds % 86400)/3600)
  local minute = floor((seconds % 3600)/60)
  local second = floor(seconds % 60)

  local ret_string = ""
  ret_string = _M.append_time(day, "day", ret_string, append_zero)
  ret_string = _M.append_time(hour, "hour", ret_string, append_zero)
  ret_string = _M.append_time(minute, "minute", ret_string, append_zero)
  ret_string = _M.append_time(second, "second", ret_string, append_zero)

  return ret_string
end


-- Validates an email address
_M.validate_email = function(str)
  if str == nil then
    return nil, "missing"
  end

  if type(str) ~= "string" then
    return nil, "must be a string"
  end

  local at = str:find("@")

  if not at then
    return nil, "missing '@' symbol"
  end

  local last_at = str:find("[^%@]+$")

  if not last_at then
    return nil, "missing domain"
  end

  local local_part = str:sub(1, (last_at - 2)) -- Returns the substring before '@' symbol
  -- we werent able to split the email properly
  if local_part == nil or local_part == "" then
    return nil, "missing local-part"
  end

  local domain_part = str:sub(last_at, #str) -- Returns the substring after '@' symbol

  -- This may be redundant
  if domain_part == nil or domain_part == "" then
    return nil, "missing domain"
  end

  -- local part is maxed at 64 characters
  if #local_part > 64 then
    return nil, "local-part over 64 characters"
  end

  -- domains are maxed at 253 characters
  if #domain_part > 253 then
    return nil, "domain over 253 characters"
  end

  local quotes = local_part:find("[\"]")
  if type(quotes) == "number" and quotes > 1 then
    return nil, "local-part invalid quotes"
  end

  if local_part:find("%@+") and quotes == nil then
    return nil, "local-part invalid '@' character"
  end

  if not domain_part:find("%.") then
    return nil, "domain missing '.' character"
  end

  if domain_part:find("%.%.") then
    return nil, "domain cannot contain consecutive '.'"
  end
  if local_part:find("%.%.") then
    return nil, "local-part cannot contain consecutive '.'"
  end

  if not str:match('[%w]*[%p]*%@+[%w]*[%.]?[%w]*') then
    return nil, "invalid format"
  end

  return true
end


_M.get_developer_status = function(consumer)
  local status = consumer.status
  return {
    status = status,
    label  = enums.CONSUMERS.STATUS_LABELS[status],
  }
end

_M.prepare_plugin = function(name, config)
  local dao = singletons.dao

  local plugin, err = _M.find_plugin(name)
  if err then
    return nil, api_helpers.yield_error(err)
  end

  local fields = {
    name = plugin.name,
    service_id = SERVICE_ID,
    config = config
  }

  -- convert plugin configuration over to model to obtain defaults
  local model = dao.plugins.model_mt(fields)

  -- validate the model
  local ok, err = model:validate({dao = dao.plugins})
  if not ok then
    return api_helpers.yield_error(err)
  end

  return {
    handler = plugin.handler,
    config = model.config,
  }
end


_M.apply_plugin = function(plugin, phase)
  local err = coroutine.wrap(plugin.handler[phase])(plugin.handler, plugin.config)
  if err then
    return api_helpers.yield_error(err)
  end
end


_M.validate_reset_jwt = function(token_param)
  -- Decode jwt
  local jwt, err = ee_jwt.parse_JWT(token_param)
  if err then
    return nil, ee_jwt.INVALID_JWT
  end

  if not jwt.header or jwt.header.typ ~= "JWT" or jwt.header.alg ~= "HS256" then
    return nil, ee_jwt.INVALID_JWT
  end

  if not jwt.claims or not jwt.claims.exp then
    return nil, ee_jwt.INVALID_JWT
  end

  if jwt.claims.exp <= time() then
    return nil, ee_jwt.EXPIRED_JWT
  end

  if not jwt.claims.id then
    return nil, ee_jwt.INVALID_JWT
  end

  return jwt
end


return _M
