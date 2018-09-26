local log        = require "kong.cmd.utils.log"
local meta       = require "kong.enterprise_edition.meta"
local pl_file    = require "pl.file"
local pl_utils   = require "pl.utils"
local pl_path    = require "pl.path"
local singletons = require "kong.singletons"
local feature_flags = require "kong.enterprise_edition.feature_flags"
local internal_statsd = require "kong.enterprise_edition.internal_statsd"
local license_helpers = require "kong.enterprise_edition.license_helpers"


local _M = {}


_M.handlers = {
  init_worker = {
    after = function(ctx)
      license_helpers.report_expired_license()
    end,
  },
  access = {
    after = function(ctx)
      if not ctx.is_internal then
        singletons.vitals:log_latency(ctx.KONG_PROXY_LATENCY)
        singletons.vitals:log_request(ctx)
      end
    end
  },
  header_filter = {
    after = function(ctx)
      if not ctx.is_internal then
        singletons.vitals:log_upstream_latency(ctx.KONG_WAITING_TIME)
      end
    end
  },
  log = {
    after = function(ctx, status)
      if not ctx.is_internal then
        singletons.vitals:log_phase_after_plugins(ctx, status)
      end
    end
  }
}


function _M.feature_flags_init(config)
  if config and config.feature_conf_path and config.feature_conf_path ~= "" then
    local _, err = feature_flags.init(config.feature_conf_path)
    if err then
      return err
    end
  end
end

function _M.internal_statsd_init()
  local _, err = internal_statsd.new()
  if err then
    return false, err
  end
  return true, nil
end

_M.read_license_info = license_helpers.read_license_info

local function write_kconfig(configs, filename)
  local kconfig_str = "window.K_CONFIG = {\n"
  for config, value in pairs(configs) do
    kconfig_str = kconfig_str .. "  '" .. config .. "': '" .. value .. "',\n"
  end

  -- remove trailing comma
  kconfig_str = kconfig_str:sub(1, -3)

  if not pl_file.write(filename, kconfig_str .. "\n}\n") then
    log.warn("Could not write file ".. filename .. ". Ensure that the Kong " ..
             "CLI user has permissions to write to this directory")
  end
end


local function prepare_interface(interface_dir, interface_env, kong_config)
  local interface_path = kong_config.prefix .. "/" .. interface_dir
  local compile_env = interface_env
  local config_filename = interface_path .. "/kconfig.js"
  local usr_interface_path = "/usr/local/kong/" .. interface_dir

  if not pl_path.exists(interface_path)
     and not pl_path.exists(usr_interface_path) then

      if not pl_path.mkdir(interface_path) then
        log.warn("Could not create directory " .. interface_path .. ". " ..
                 "Ensure that the Kong CLI user has permissions to create " ..
                 "this directory.")
      end
  end

  -- if the interface directory does not exist, try symlinking it to its default
  -- prefix location. This occurs in development environments where the
  -- gui does not exist (it is bundled at build time), so this effectively
  -- serves to quiet useless warnings in kong-ee development
  if usr_interface_path ~= interface_path
     and pl_path.exists(usr_interface_path) then
    local ln_cmd = "ln -s " .. usr_interface_path .. " " .. interface_path
    pl_utils.executeex(ln_cmd)
  end

  write_kconfig(compile_env, config_filename)
end

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


function _M.prepare_admin(kong_config)
  local gui_listen = select_listener(kong_config.admin_gui_listeners, {ssl = false})
  local gui_port = gui_listen and gui_listen.port
  local gui_ssl_listen = select_listener(kong_config.admin_gui_listeners, {ssl = true})
  local gui_ssl_port = gui_ssl_listen and gui_ssl_listen.port

  local api_url
  local api_listen
  local api_port
  local api_ssl_listen
  local api_ssl_port

  -- only access the admin API on the proxy if auth is enabled
  if kong_config.admin_gui_auth then
    api_listen = select_listener(kong_config.proxy_listeners, {ssl = false})
    api_port = api_listen and api_listen.port
    api_ssl_listen = select_listener(kong_config.proxy_listeners, {ssl = true})
    api_ssl_port = api_ssl_listen and api_ssl_listen.port
    api_url = kong_config.proxy_url
  else
    api_listen = select_listener(kong_config.admin_listeners, {ssl = false})
    api_port = api_listen and api_listen.port
    api_ssl_listen = select_listener(kong_config.admin_listeners, {ssl = true})
    api_ssl_port = api_ssl_listen and api_ssl_listen.port
    -- TODO: stop using this property, and introduce admin_api_url so that
    -- api_url always includes the protocol
    api_url = kong_config.admin_api_uri
  end

  -- we will consider rbac to be on if it is set to "both" or "on",
  -- because we don't currently support entity-level
  local rbac_enforced = kong_config.rbac == "both" or kong_config.rbac == "on"

  return prepare_interface("gui", {
    ADMIN_GUI_AUTH = prepare_variable(kong_config.admin_gui_auth),
    ADMIN_GUI_URL = prepare_variable(kong_config.admin_gui_url),
    ADMIN_GUI_PORT = prepare_variable(gui_port),
    ADMIN_GUI_SSL_PORT = prepare_variable(gui_ssl_port),
    ADMIN_API_URL = prepare_variable(api_url),
    ADMIN_API_PORT = prepare_variable(api_port),
    ADMIN_API_SSL_PORT = prepare_variable(api_ssl_port),
    RBAC = prepare_variable(kong_config.rbac),
    RBAC_ENFORCED = prepare_variable(rbac_enforced),
    RBAC_HEADER = prepare_variable(kong_config.rbac_auth_header),
    KONG_VERSION = prepare_variable(meta.versions.package),
    FEATURE_FLAGS = prepare_variable(kong_config.admin_gui_flags),
  }, kong_config)
end


function _M.prepare_portal(kong_config)
  local portal_gui_listener = select_listener(kong_config.portal_gui_listeners,
                                              {ssl = false})
  local portal_gui_ssl_listener = select_listener(kong_config.portal_gui_listeners,
                                                  {ssl = true})
  local portal_gui_port = portal_gui_listener and portal_gui_listener.port
  local portal_gui_ssl_port = portal_gui_ssl_listener and portal_gui_ssl_listener.port
  local portal_api_listener = select_listener(kong_config.portal_api_listeners,
                                         {ssl = false})
  local portal_api_ssl_listener = select_listener(kong_config.portal_api_listeners,
                                             {ssl = true})
  local portal_api_port = portal_api_listener and portal_api_listener.port
  local portal_api_ssl_port = portal_api_ssl_listener and portal_api_ssl_listener.port

  local rbac_enforced = kong_config.rbac == "both" or kong_config.rbac == "on"

  return prepare_interface("portal", {
    PORTAL_API_URL = prepare_variable(kong_config.portal_api_url),
    PORTAL_AUTH = prepare_variable(kong_config.portal_auth),
    PORTAL_API_PORT = prepare_variable(portal_api_port),
    PORTAL_API_SSL_PORT = prepare_variable(portal_api_ssl_port),
    PORTAL_GUI_URL = prepare_variable(kong_config.portal_gui_url),
    PORTAL_GUI_PORT = prepare_variable(portal_gui_port),
    PORTAL_GUI_SSL_PORT = prepare_variable(portal_gui_ssl_port),
    RBAC_ENFORCED = prepare_variable(rbac_enforced),
    RBAC_HEADER = prepare_variable(kong_config.rbac_auth_header),
    KONG_VERSION = prepare_variable(meta.versions.package),
  }, kong_config)
end


return _M
