local meta       = require "kong.meta"

local _M = {}

-- return first listener matching filters
local function select_listener(listeners, filters)
  for _, listener in ipairs(listeners) do
    local match = true
    for filter, value in pairs(filters) do
      if listener[filter] ~= value then
        match = false
      end
    end
    if match then
      return listener
    end
  end
end

local function prepare_variable(variable)
  if variable == nil then
    return ""
  end

  return tostring(variable)
end

function _M.generate_kconfig(kong_config)
  local api_listen = select_listener(kong_config.admin_listeners, {ssl = false})
  local api_port = api_listen and api_listen.port
  local api_ssl_listen = select_listener(kong_config.admin_listeners, {ssl = true})
  local api_ssl_port = api_ssl_listen and api_ssl_listen.port

  local configs = {
    ADMIN_GUI_URL = prepare_variable(kong_config.admin_gui_url),
    ADMIN_GUI_PATH = prepare_variable(kong_config.admin_gui_path),
    ADMIN_API_URL = prepare_variable(kong_config.admin_gui_api_url),
    ADMIN_API_PORT = prepare_variable(api_port),
    ADMIN_API_SSL_PORT = prepare_variable(api_ssl_port),
    KONG_VERSION = prepare_variable(meta.version),
    KONG_EDITION = "community",
    ANONYMOUS_REPORTS = prepare_variable(kong_config.anonymous_reports),
  }

  local kconfig_str = "window.K_CONFIG = {\n"
  for config, value in pairs(configs) do
    kconfig_str = kconfig_str .. "  '" .. config .. "': '" .. value .. "',\n"
  end

  -- remove trailing comma
  kconfig_str = kconfig_str:sub(1, -3)

  return kconfig_str .. "\n}\n"
end

return _M
