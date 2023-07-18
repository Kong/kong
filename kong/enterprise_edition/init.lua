-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local pl_utils   = require "pl.utils"
local pl_path    = require "pl.path"

local log        = require "kong.cmd.utils.log"
local meta       = require "kong.enterprise_edition.meta"
local constants  = require "kong.constants"
local workspaces = require "kong.workspaces"
local feature_flags   = require "kong.enterprise_edition.feature_flags"
local license_helpers = require "kong.enterprise_edition.license_helpers"
local event_hooks = require "kong.enterprise_edition.event_hooks"
local rbac = require "kong.rbac"
local hooks = require "kong.hooks"
local ee_api = require "kong.enterprise_edition.api_helpers"
local ee_status_api = require "kong.enterprise_edition.status"
local utils = require "kong.tools.utils"
local app_helpers = require "lapis.application"
local api_helpers = require "kong.api.api_helpers"
local tracing = require "kong.tracing"
local counters = require "kong.workspaces.counters"
local workspace_config = require "kong.portal.workspace_config"
local websocket = require "kong.enterprise_edition.runloop.websocket"

local cjson = require "cjson.safe"

local fmt = string.format

local kong = kong
local ngx  = ngx
local ws_constants  = constants.WORKSPACE_CONFIG
local _M = {}

require "kong.enterprise_edition.debug_info_patch"

_M.handlers = {
  init = {
    after = function()

      rbac.register_dao_hooks(kong.db)
      counters.register_dao_hooks()

      hooks.register_hook("api:init:pre", function(app)
        app:before_filter(ee_api.before_filter)

        for _, v in ipairs({"vitals", "license",
                            "entities", "keyring"}) do

          local routes = require("kong.api.routes." .. v)
          api_helpers.attach_routes(app, routes)
        end

        -- attach `/:workspace/kong`, which replicates `/`
        local slash_handler = require "kong.api.routes.kong"["/"]
        -- EE add support for HEAD calls (GET without body)
        slash_handler["HEAD"] = slash_handler["GET"]
        app:match("/:workspace_name/kong", "/:workspace_name/kong",
                  app_helpers.respond_to(slash_handler))

        return true
      end)

      hooks.register_hook("api:init:post", function(app, routes)
        for _, k in ipairs({"rbac", "audit"}) do
          local loaded, mod = utils.load_module_if_exists("kong.api.routes.".. k)
          if loaded then
            ngx.log(ngx.DEBUG, "Loading API endpoints for module: ", k)
            if api_helpers.is_new_db_routes(mod) then
              api_helpers.attach_new_db_routes(app, mod)
            else
              api_helpers.attach_routes(app, mod)
            end

          else
            ngx.log(ngx.DEBUG, "No API endpoints loaded for module: ", k)
          end
        end

        ee_api.splatify_entity_route("files", routes)

        return true
      end)

      hooks.register_hook("status_api:init:pre", function(app)
        app:before_filter(ee_status_api.before_filter)

        return true
      end)

      local function prepend_workspace_prefix(app, route_path, methods)
        if route_path ~= "/" then
          app:match("workspace_" .. route_path, "/:workspace_name" .. route_path,
          app_helpers.respond_to(methods))
        end

        return true
      end

      hooks.register_hook("api:helpers:attach_routes", prepend_workspace_prefix)
      hooks.register_hook("api:helpers:attach_new_db_routes", prepend_workspace_prefix)

      hooks.register_hook("balancer:get_peer:pre", function(target_host)
        return tracing.trace("balancer.getPeer", { qname = target_host })
      end)

      hooks.register_hook("balancer:get_peer:post", function(trace)
        trace:finish()
      end)

      hooks.register_hook("balancer:to_ip:pre", function(target_host)
        return tracing.trace("balancer.toip", { qname = target_host })
      end)

      hooks.register_hook("balancer:to-ip:post", function(trace)
        trace:finish()
      end)
    end
  },
  init_worker = {
    after = function(ctx)
      if kong.configuration.admin_gui_listeners then
        kong.cache:invalidate_local(constants.ADMIN_GUI_KCONFIG_CACHE_KEY)
      end

      kong.licensing:init_worker()

      -- register actions on configuration change (ie: license)
      --   * anything that _always_ checks on runtime for a config will
      --     work without any further change (rbac)
      --   * things that check for settings only on init won't work unless
      --     we handle the change (see vitals on kong/init.lua)
      kong.worker_events.register(function(data, event, source, pid)
        kong.cache:invalidate_local(constants.ADMIN_GUI_KCONFIG_CACHE_KEY)
      end, "kong:configuration", "change")

      -- register event_hooks hooks
      event_hooks.register_events(kong.worker_events)
    end,
  },
  header_filter = {
    after = function(ctx)
      if not ctx.is_internal then
        kong.vitals:log_upstream_latency(ctx.KONG_WAITING_TIME)
      end
    end
  },
  log = {
    after = function(ctx, status)
      tracing.flush()

      if not ctx.is_internal then
        kong.vitals:log_latency(ctx.KONG_PROXY_LATENCY)
        kong.vitals:log_request(ctx)
        kong.sales_counters:log_request()
        kong.vitals:log_phase_after_plugins(ctx, status)
      end
    end
  },

  ws_handshake = websocket.handlers.ws_handshake,
  ws_proxy = websocket.handlers.ws_proxy,
  ws_close = websocket.handlers.ws_close,
}


function _M.feature_flags_init(config)
  if config and config.feature_conf_path and config.feature_conf_path ~= "" then
    local _, err = feature_flags.init(config.feature_conf_path)
    if err then
      return err
    end
  end
end


local function render_kconfig(configs)
  local kconfig_str = "window.K_CONFIG = {\n"
  for config, value in pairs(configs) do
    kconfig_str = kconfig_str .. "  '" .. config .. "': '" .. value .. "',\n"
  end

  -- remove trailing comma
  kconfig_str = kconfig_str:sub(1, -3)
  kconfig_str = kconfig_str .. "\n}\n"
  return kconfig_str
end

local function prepare_interface(usr_path, interface_dir, kong_config)
  local usr_interface_path = usr_path .. "/" .. interface_dir
  local interface_path = kong_config.prefix .. "/" .. interface_dir

  -- if the interface directory is not exist in custom prefix directory
  -- try symlinking to the default prefix location
  -- ensure user can access the interface appliation
  if not pl_path.exists(interface_path)
     and pl_path.exists(usr_interface_path) then

    local ln_cmd = "ln -s " .. usr_interface_path .. " " .. interface_path
    local ok, _, _, err_t = pl_utils.executeex(ln_cmd)

    if not ok then
      log.warn(err_t)
    end
  end
end

_M.prepare_interface = prepare_interface
_M.render_kconfig = render_kconfig

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

  local api_listen
  local api_port
  local api_ssl_listen
  local api_ssl_port

  -- only access the admin API on the proxy if auth is enabled
  api_listen = select_listener(kong_config.admin_listeners, {ssl = false})
  api_port = api_listen and api_listen.port
  api_ssl_listen = select_listener(kong_config.admin_listeners, {ssl = true})
  api_ssl_port = api_ssl_listen and api_ssl_listen.port

  -- we will consider rbac to be on if it is set to "both" or "on",
  -- because we don't currently support entity-level
  local rbac_enforced = kong_config.rbac == "both" or kong_config.rbac == "on"

  return render_kconfig({
    ADMIN_GUI_AUTH = prepare_variable(kong_config.admin_gui_auth),
    ADMIN_GUI_URL = prepare_variable(kong_config.admin_gui_url),
    ADMIN_GUI_PATH = prepare_variable(kong_config.admin_gui_path),
    ADMIN_GUI_PORT = prepare_variable(gui_port),
    ADMIN_GUI_SSL_PORT = prepare_variable(gui_ssl_port),
    ADMIN_API_URL = prepare_variable(kong_config.admin_gui_api_url),
    ADMIN_API_PORT = prepare_variable(api_port),
    ADMIN_API_SSL_PORT = prepare_variable(api_ssl_port),
    ADMIN_GUI_HEADER_TXT = prepare_variable(kong_config.admin_gui_header_txt),
    ADMIN_GUI_HEADER_BG_COLOR = prepare_variable(kong_config.admin_gui_header_bg_color),
    ADMIN_GUI_HEADER_TXT_COLOR = prepare_variable(kong_config.admin_gui_header_txt_color),
    ADMIN_GUI_FOOTER_TXT = prepare_variable(kong_config.admin_gui_footer_txt),
    ADMIN_GUI_FOOTER_BG_COLOR = prepare_variable(kong_config.admin_gui_footer_bg_color),
    ADMIN_GUI_FOOTER_TXT_COLOR = prepare_variable(kong_config.admin_gui_footer_txt_color),
    ADMIN_GUI_LOGIN_BANNER_TITLE = prepare_variable(kong_config.admin_gui_login_banner_title),
    ADMIN_GUI_LOGIN_BANNER_BODY = prepare_variable(kong_config.admin_gui_login_banner_body),
    RBAC = prepare_variable(kong_config.rbac),
    RBAC_ENFORCED = prepare_variable(rbac_enforced),
    RBAC_HEADER = prepare_variable(kong_config.rbac_auth_header),
    RBAC_USER_HEADER = prepare_variable(kong_config.admin_gui_auth_header),
    KONG_VERSION = prepare_variable(meta.version),
    KONG_EDITION = "enterprise",
    FEATURE_FLAGS = prepare_variable(kong_config.admin_gui_flags),
    PORTAL = prepare_variable(kong_config.portal),
    PORTAL_GUI_PROTOCOL = prepare_variable(kong_config.portal_gui_protocol),
    PORTAL_GUI_HOST = prepare_variable(kong_config.portal_gui_host),
    PORTAL_GUI_USE_SUBDOMAINS = prepare_variable(kong_config.portal_gui_use_subdomains),
    ANONYMOUS_REPORTS = prepare_variable(kong_config.anonymous_reports),
  })
end


function _M.prepare_portal(self, kong_config)
  local workspace = workspaces.get_workspace()
  local is_authenticated = self.developer ~= nil

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

  local portal_gui_url = workspace_config.build_ws_portal_gui_url(kong_config, workspace)
  local portal_auth = workspace_config.retrieve(ws_constants.PORTAL_AUTH, workspace)

  local opts = { explicitly_ws = true }
  local portal_developer_meta_fields = workspace_config.retrieve(
                            ws_constants.PORTAL_DEVELOPER_META_FIELDS,
                            workspace, opts) or '[]'

  return {
    PORTAL_API_URL = prepare_variable(kong_config.portal_api_url),
    PORTAL_AUTH = prepare_variable(portal_auth),
    PORTAL_API_PORT = prepare_variable(portal_api_port),
    PORTAL_API_SSL_PORT = prepare_variable(portal_api_ssl_port),
    PORTAL_GUI_URL = prepare_variable(portal_gui_url),
    PORTAL_GUI_PORT = prepare_variable(portal_gui_port),
    PORTAL_GUI_SSL_PORT = prepare_variable(portal_gui_ssl_port),
    PORTAL_IS_AUTHENTICATED = prepare_variable(is_authenticated),
    PORTAL_GUI_USE_SUBDOMAINS = prepare_variable(kong_config.portal_gui_use_subdomains),
    PORTAL_DEVELOPER_META_FIELDS = prepare_variable(portal_developer_meta_fields),
    RBAC_ENFORCED = prepare_variable(rbac_enforced),
    RBAC_HEADER = prepare_variable(kong_config.rbac_auth_header),
    KONG_VERSION = prepare_variable(meta.version),
    WORKSPACE = prepare_variable(workspace.name)
  }
end


function _M.license_hooks(config)

  local nop = function() end

  -- license API allow / deny
  hooks.register_hook("api:init:pre", function(app)
    app:before_filter(license_helpers.license_can_proceed)

    return true
  end)

  -- add license info
  hooks.register_hook("api:kong:info", function(info)
    if kong.license and kong.license.license and kong.license.license.payload then
      info.license = utils.cycle_aware_deep_copy(kong.license.license.payload)
      info.license.license_key = nil
    end

    return info
  end)

  -- add EE disabled plugins
  hooks.register_hook("api:kong:info", function(info)

    -- do nothing
    if kong.licensing:can("ee_plugins") then
      info.plugins.disabled_on_server = {}

      return info
    end

    -- very careful modifying `info.plugins.available_on_server` since it
    -- will affect `kong.configuration.loaded_plugins` by reference

    info.plugins.available_on_server = constants.CE_PLUGINS_MAP
    info.plugins.disabled_on_server = constants.EE_PLUGINS_MAP

    -- remove EE plugins from `info.plugins.enabled_in_cluster`, even if its
    -- configured it won't run

    local cluster = setmetatable({}, cjson.array_mt)
    local _cluster = info.plugins.enabled_in_cluster

    for i = 1, #_cluster do
      if not constants.EE_PLUGINS_MAP[_cluster[i]] then
        cluster[#cluster + 1] = _cluster[i]
      end
    end

    info.plugins.enabled_in_cluster = cluster

    return info
  end)


  local function wrap_method(thing, name, method)
    thing[name] = method(thing[name] or nop)
  end

  local phase_checker = require "kong.pdk.private.phases"

  local function patch_handler(handler, name)
    for phase, _ in pairs(phase_checker.phases) do

      -- TODO: only patch each phase handler once
      if handler[phase] and phase ~= 'init_worker'
         and type(handler[phase]) == "function"
      then -- only patch the handler if overriden by plugin

        wrap_method(handler, phase, function(parent)
          return function(...)
            ngx.log(ngx.DEBUG, fmt("calling patched method '%s:%s'", name, phase))
            if not kong.licensing:can("ee_plugins") then
              ngx.log(ngx.DEBUG, fmt("nop'ing '%s:%s, ee_plugins=false", name, phase))
              return
            end

            return parent(...)
          end
        end)
      end
    end

    return handler
  end

  -- XXX For now, this uses the strategy of patching all EE plugin handlers
  -- we have arrived here fishing for a bug. Many strategies were tried, but
  -- the bug persisted. The bug ended up being something small not really
  -- related to the strategy, so we do not know if any of the methods we tried
  -- were good or not. But we know this one (a bit overkill) works
  -- XXX: come back and try the different elegant strategies
  hooks.register_hook("dao:plugins:load", function(handlers)

    for plugin, _ in pairs(constants.EE_PLUGINS_MAP) do
      if handlers[plugin] then
        handlers[plugin] = patch_handler(handlers[plugin], plugin)
      end
    end

    return true
  end)

  local err = function(...)
    return fmt("'%s' is an enterprise only %s", ...)
  end

  -- XXX return here if data_plane. Data plane needs to get a config from the
  -- control plane, that will include a license + entities that it needs
  -- to accept. If we restrict these, then it does not work
  if config.role == "data_plane" then
    return
  end

  -- API and entity restriction be here

  -- disable EE plugins on the entity level
  -- XXX Check performance penalty on these
  hooks.register_hook("db:schema:plugins:new", function(entity, name)

    wrap_method(entity, "validate", function(parent)
      return function(self, input, ...)

        local name = input.name

        if not kong.licensing:can("ee_plugins") and constants.EE_PLUGINS_MAP[name] then
          return nil, { name = err(name, "plugin") }
        end

        return parent(self, input, ...)
      end
    end)

    return true
  end)


  local function get_plugin_entities(plugin)
    local has_daos, daos_schemas = utils.load_module_if_exists("kong.plugins." .. plugin .. ".daos")
    if not has_daos then
      return nop
    end

    local it = daos_schemas[1] and ipairs or pairs

    return it(daos_schemas)
  end


  local function forbidden()
    return kong.response.exit(403, { message = "Enterprise license missing or expired" })
  end


  -- disable EE plugins entities and custom api endpoints
  -- XXX Check performance penalty on these
  local enterprise_plugin_entities = {}

  for _, plugin in ipairs(constants.EE_PLUGINS) do
    for _, schema in get_plugin_entities(plugin) do
      enterprise_plugin_entities[schema.name] = true
    end
  end

  hooks.register_hook("db:schema:entity:new", function(entity, name)

    local hit = enterprise_plugin_entities[name]
    local err = { licensing = err(name, "entity") }

    wrap_method(entity, "validate", function(parent)
      return function(...)

        if hit and not kong.licensing:can("ee_plugins") then
          return nil, err
        end

        local deny_entity = kong.licensing.deny_entity

        if deny_entity and deny_entity[name] then
          return nil, err
        end

        return parent(...)
      end
    end)

    return true
  end)

  hooks.register_hook("api:helpers:attach_new_db_routes:before", function(app, route_path, methods, schema)

    local hit = enterprise_plugin_entities[schema.name]

    wrap_method(methods, "before", function(parent)
      return function(...)

        if hit and not kong.licensing:can("ee_plugins") then
          return forbidden()
        end

        local deny_entity = kong.licensing.deny_entity

        if deny_entity and deny_entity[schema.name] then
          return forbidden()
        end

        return parent(...)
      end
    end)

    return true
  end)

end


return _M
