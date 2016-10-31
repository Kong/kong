local stringy = require "stringy"
local oxd = require "kong.plugins.kong-uma-rs.oxdclient"

local function isempty(s)
  return s == nil or s == ''
end

local function protection_document_validator(given_value, given_config)

  ngx.log(ngx.DEBUG, "protection_document_validator: given_value:" .. given_value)

  if isempty(given_value) then
    ngx.log(ngx.ERROR, "Invalid protection_document. It is blank.")
    return false
  end

  return true
end

local function host_validator(given_value, given_config)
  ngx.log(ngx.DEBUG, "host_validator: given_value:" .. given_value)

  if isempty(given_value) then
    ngx.log(ngx.ERROR, "Invalid oxd_host. It is blank.")
    return false
  end

  return true
end

local function port_validator(given_value, given_config)
  ngx.log(ngx.DEBUG, "port_validator: given_value:" .. given_value)

  if given_value <= 0 then
    ngx.log(ngx.ERROR, "Invalid oxd_port. It is less or equals to zero.")
    return false
  end

  return true
end

local function uma_server_host_validator(given_value, given_config)
  ngx.log(ngx.DEBUG, "uma_server_host_validator: given_value:" .. given_value)

  if isempty(given_value) then
    ngx.log(ngx.ERROR, "Invalid uma_server_host. It is blank.")
    return false
  end

  if isempty(given_value) then
    ngx.log(ngx.ERROR, "Invalid uma_server_host. It is blank.")
    return false
  end

  if not stringy.startswith(given_value, "https://") then
    ngx.log(ngx.ERROR, "Invalid uma_server_host. It does not start from 'https://', value: " .. given_value)
    return false
  end

  return true
end

return {
  no_consumer = true,
  fields = {
    oxd_host = { required = true, type = "string", func = host_validator },
    oxd_port = { required = true, type = "number", func = port_validator },
    uma_server_host = { required = true, type = "string", func = uma_server_host_validator },
    protection_document = { required = true, type = "string", func = protection_document_validator },
  },
  self_check = function(schema, plugin_t, dao, is_updating)
    return oxd.register(plugin_t), "Failed to register API on oxd server (make sure oxd server is running on oxd_host and oxd_port specified in configuration)"
  end
}