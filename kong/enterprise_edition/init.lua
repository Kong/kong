-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local constants  = require "kong.constants"
local ee_constants = require "kong.enterprise_edition.constants"
local workspaces = require "kong.workspaces"
local feature_flags   = require "kong.enterprise_edition.feature_flags"
local license_helpers = require "kong.enterprise_edition.license_helpers"
local event_hooks = require "kong.enterprise_edition.event_hooks"
local rbac = require "kong.rbac"
local hooks = require "kong.hooks"
local ee_api = require "kong.enterprise_edition.api_helpers"
local ee_status_api = require "kong.enterprise_edition.status"
local app_helpers = require "lapis.application"
local api_helpers = require "kong.api.api_helpers"
local tracing = require "kong.tracing"
local counters = require "kong.workspaces.counters"
local workspace_config = require "kong.portal.workspace_config"
local websocket = require "kong.enterprise_edition.runloop.websocket"
local admin_gui_utils = require "kong.admin_gui.utils"
local openssl = require "resty.openssl"
local openssl_version = require "resty.openssl.version"
local load_module_if_exists = require "kong.tools.module".load_module_if_exists
local cycle_aware_deep_copy = require "kong.tools.table".cycle_aware_deep_copy

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
          local loaded, mod = load_module_if_exists("kong.api.routes.".. k)
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
      kong.licensing:init_worker()

      -- register actions on configuration change (ie: license)
      --   * anything that _always_ checks on runtime for a config will
      --     work without any further change (rbac)
      --   * things that check for settings only on init won't work unless
      --     we handle the change (see vitals on kong/init.lua)
      kong.worker_events.register(function(data, event, source, pid)
        kong.cache:invalidate_local(constants.ADMIN_GUI_KCONFIG_CACHE_KEY)
        kong.cache:invalidate_local(ee_constants.PORTAL_VITALS_ALLOWED_CACHE_KEY)
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


function _M.prepare_portal(self, kong_config)
  local workspace = workspaces.get_workspace()
  local is_authenticated = self.developer ~= nil

  local portal_gui_listener = admin_gui_utils.select_listener(kong_config.portal_gui_listeners,
                                              {ssl = false})
  local portal_gui_ssl_listener = admin_gui_utils.select_listener(kong_config.portal_gui_listeners,
                                                  {ssl = true})
  local portal_gui_port = portal_gui_listener and portal_gui_listener.port
  local portal_gui_ssl_port = portal_gui_ssl_listener and portal_gui_ssl_listener.port
  local portal_api_listener = admin_gui_utils.select_listener(kong_config.portal_api_listeners,
                                         {ssl = false})
  local portal_api_ssl_listener = admin_gui_utils.select_listener(kong_config.portal_api_listeners,
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
    PORTAL_API_URL = admin_gui_utils.prepare_variable(kong_config.portal_api_url),
    PORTAL_AUTH = admin_gui_utils.prepare_variable(portal_auth),
    PORTAL_API_PORT = admin_gui_utils.prepare_variable(portal_api_port),
    PORTAL_API_SSL_PORT = admin_gui_utils.prepare_variable(portal_api_ssl_port),
    PORTAL_GUI_URL = admin_gui_utils.prepare_variable(portal_gui_url),
    PORTAL_GUI_PORT = admin_gui_utils.prepare_variable(portal_gui_port),
    PORTAL_GUI_SSL_PORT = admin_gui_utils.prepare_variable(portal_gui_ssl_port),
    PORTAL_IS_AUTHENTICATED = admin_gui_utils.prepare_variable(is_authenticated),
    PORTAL_GUI_USE_SUBDOMAINS = admin_gui_utils.prepare_variable(kong_config.portal_gui_use_subdomains),
    PORTAL_DEVELOPER_META_FIELDS = admin_gui_utils.prepare_variable(portal_developer_meta_fields),
    RBAC_ENFORCED = admin_gui_utils.prepare_variable(rbac_enforced),
    WORKSPACE = admin_gui_utils.prepare_variable(workspace.name)
  }
end


function _M.license_hooks(config)

  local nop = function() end

  -- license API allow / deny
  hooks.register_hook("api:init:pre", function(app)
    app:before_filter(license_helpers.license_can_proceed)

    return true
  end)

  -- fips validation
  hooks.register_hook("fips:kong:validate", function(l_type)
    if l_type == 'free' then
      kong.log.warn("FIPS mode is not supported in Free mode. Please reach out to " ..
                    "Kong if you are interested in using Kong FIPS compliant artifacts")
      return
    end

    local ok, err = openssl.set_fips_mode(true)
    if not ok or not openssl.get_fips_mode() then
      kong.log.err("cannot enable FIPS mode: " .. (err or "nil"))
      return
    end

    kong.log.warn("enabling FIPS mode on ", openssl_version.version_text,
                  " (", openssl_version.version(openssl_version.CFLAGS), ")")
  end)

  -- add license info
  hooks.register_hook("api:kong:info", function(info)
    if kong.license and kong.license.license and kong.license.license.payload then
      info.license = cycle_aware_deep_copy(kong.license.license.payload)
      info.license.license_key = nil
    end

    return info
  end)

  -- add EE disabled plugins
  hooks.register_hook("api:kong:info", function(info)

    -- do nothing
    if kong.licensing:allow_ee_entity("READ") then
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

      if handler[phase] and phase ~= 'init_worker'
         and type(handler[phase]) == "function"
      then -- only patch the handler if overriden by plugin

        wrap_method(handler, phase, function(parent)
          return function(...)
            ngx.log(ngx.DEBUG, fmt("calling patched method '%s:%s'", name, phase))
            if not kong.licensing:allow_ee_entity("READ") then
              ngx.log(ngx.DEBUG, fmt("nop'ing '%s:%s, ee_plugins[READ]=false", name, phase))
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

        if not kong.licensing:allow_ee_entity("WRITE") and constants.EE_PLUGINS_MAP[name] then
          return nil, { name = err(name, "plugin") }
        end

        return parent(self, input, ...)
      end
    end)

    return true
  end)


  local function get_plugin_entities(plugin)
    local has_daos, daos_schemas = load_module_if_exists("kong.plugins." .. plugin .. ".daos")
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
  local enterprise_plugin_entities = {}

  for _, plugin in ipairs(constants.EE_PLUGINS) do
    for _, schema in get_plugin_entities(plugin) do
      enterprise_plugin_entities[schema.name] = true
    end
  end

  -- XXX We can't limit reads and writes at the entity level because some plugins
  -- have rediscover capabilities that require updating the database on their own. e.g. openid-connect
  hooks.register_hook("db:schema:entity:new", function(entity, name)

    local err = { licensing = err(name, "entity") }

    wrap_method(entity, "validate", function(parent)
      return function(...)

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

    local is_disabled = enterprise_plugin_entities[schema.name]

    wrap_method(methods, "before", function(parent)
      return function(...)

        local disabled_ee_entities = kong.licensing.disabled_ee_entities

        if is_disabled or (disabled_ee_entities and disabled_ee_entities[schema.name]) then
          local method = ngx.req.get_method()
          local operator = "WRITE"

          if method == "GET" or method == "OPTIONS" then
            operator = "READ"
          end

          if not kong.licensing:allow_ee_entity(operator) then
            return forbidden()
          end
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

  local function validate_ee_plugins(entity, name)
    if name ~= "plugins" then
      return entity
    end

    if constants.EE_PLUGINS_MAP[entity.name] and not kong.licensing:allow_ee_entity("WRITE") then
      return forbidden()
    end

    return entity
  end

  hooks.register_hook("dao:delete:pre", validate_ee_plugins)
end


return _M
