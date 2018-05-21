local singletons = require "kong.singletons"
local url = require "socket.url"
local utils = require "kong.tools.utils"


local _M = {}
local mt = { __index = _M }


_M.proxy_prefix = "_kong"


-- todo move this into helpers
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


local function get_service_config(service, default_port)
  local kong_config = singletons.configuration
  local service_url = kong_config[service .. "_url"]
  local service_listeners = kong_config[service .. "_listeners"]
  local protocol = "http"
  local port = default_port

  if service_url then
    return {
      url = service_url,
    }
  end

  local listener = service_listeners and (
    select_listener(service_listeners, {ssl = true})
    or select_listener(service_listeners, {ssl = false})
  )

  if listener then
    return {
      port = listener.port,
      host = listener.host,
      protocol = listener.ssl and "https" or "http",
    }
  end

  return {
    port = port,
    protocol = protocol,
  }
end


function _M.new(opts)
  opts = opts or {}

  -- Setup metatable
  local self = {
    config = {
      services = {},
      plugins = {},
      routes = {},
    }
  }

  local cls = setmetatable(self, mt)

  cls:setup_portal()

  if opts.services then
    for i = 1, #opts.services do
      cls:add_service(opts.services[i])
    end
  end

  if opts.plugins then
    for i = 1, #opts.plugins do
      cls:add_plugin(opts.plugins[i])
    end
  end

  if opts.routes then
    for i = 1, #opts.routes do
      cls:add_route(opts.routes[i])
    end
  end

  return cls
end


function _M:setup_admin()
  local admin_config = get_service_config("admin", 8001)

  admin_config.id = "00000000-0000-0000-0000-000000000001"
  admin_config.name = "__kong_manager_api"

  self:add_service(admin_config)
  self:add_route({
    id = "00000000-0000-0000-0001-000000000000",
    service = admin_config.name,
    paths = { "/" .. _M.proxy_prefix .. "/manager" },
  })
end


function _M:setup_portal()
  local kong_config = singletons.configuration
  local proxy_enabled = kong_config.portal_auth and kong_config.proxy_listen
  local portal_enabled = kong_config.portal
  if not proxy_enabled and not portal_enabled then
    ngx.log(ngx.DEBUG, "not enabling internal service for Dev Portal ",
                       "proxy_enabled=", proxy_enabled, " ",
                       "portal_enabled=", portal_enabled)
    return
  end

  local portal_config = get_service_config("portal_api", 8004)

  portal_config.id = "00000000-0000-0000-0000-000000000001"
  portal_config.name = "__kong_portal_api"

  self:add_service(portal_config)
  self:add_route({
    id = "00000000-0000-0000-0002-000000000000",
    service = portal_config.name,
    paths = { "/" .. _M.proxy_prefix .. "/portal" },
  })

  self:add_plugin({
    name = "cors",
    service = portal_config.name,
    config = {
      origins = kong_config.portal_gui_url or "*",
      methods = { "GET", "PATCH", "DELETE", "POST" },
      credentials = true
    }
  })

  -- Enable authentication
  if kong_config.portal_auth then

    self:add_plugin({
      name = kong_config.portal_auth,
      service = portal_config.name,
      config = kong_config.portal_auth_conf or {}
    })

    local portal_config_unauthenticated = utils.shallow_copy(portal_config)

    portal_config_unauthenticated.name ="_kong-portal-files-unauthenticated"
    portal_config_unauthenticated.id = "00000000-0000-0000-0000-000000000003"
    portal_config_unauthenticated.path = "/files/unauthenticated"

    self:add_service(portal_config_unauthenticated)

    self:add_route({
      id = "00000000-0000-0000-0003-000000000000",
      service = portal_config_unauthenticated.name,
      paths = { "/" .. _M.proxy_prefix .. "/portal/files/unauthenticated" },
    })

    local portal_config_register = utils.shallow_copy(portal_config)

    portal_config_register.name ="_kong-portal-register"
    portal_config_register.id = "00000000-0000-0000-0000-000000000004"
    portal_config_register.path = "/portal/register"

    self:add_service({
      id = portal_config_register.id,
      name = portal_config_register.name,
      host = portal_config.host,
      port = portal_config.port,
      protocol = portal_config.protocol,
      path = portal_config_register.path
    })

    self:add_route({
      id = "00000000-0000-0000-0004-000000000000",
      service = portal_config_register.name,
      paths = { "/" .. _M.proxy_prefix .. "/portal/register" },
    })

    self:add_plugin({
      name = "cors",
      service = portal_config_unauthenticated.name,
      config = {
        origins = kong_config.portal_gui_url or "*",
        methods = { "GET" },
        credentials = true
      }
    })
  end
end


function _M:has_service(service_id)
  return self.config.services[service_id]
end


function _M:add_service(config)
  if config.url then
    local parsed_url, err = url.parse(config.url)
    if err then
      ngx.log(ngx.ERR, "could not parse url for internal service: ",
                       config.url)
      return
    end
    config.protocol = parsed_url.scheme
    config.host     = parsed_url.host
    config.port     = tonumber(parsed_url.port) or parsed_url.port
    config.path     = parsed_url.path
    config.url      = nil
  end

  self.config.services[config.id] = config
  self.config.services[config.name] = self.config.services[config.id]
end


function _M:add_route(config)
  if type(config.service) == "string" then
    config.service = {
      id = self.config.services[config.service].id,
    }
  end

  table.insert(self.config.routes, config)
end


function _M:add_plugin(config)
  local dao = singletons.dao

  -- lookup internal service by name
  if config.service then
    local service = self.config.services[config.service]
    if not service then
      ngx.log(ngx.ERR, "could not find internal service: ", config.service)
    end

    config.service_id = service.id
    config.service = nil
  end

  -- convert plugin configuration over to model to obtain defaults
  local model = dao.plugins.model_mt(config)
  local ok, err = model:validate {dao = dao.plugins}
  if not ok then
    ngx.log(ngx.ERR, "could not validate internal plugin: ", err)
  end

  table.insert(self.config.plugins, model)
end


function _M:build_routes(i, routes)
  local i_routes = self.config.routes
  local i_services = self.config.services
  for internal_route_index = 1, #i_routes do
    local route = i_routes[internal_route_index]
    local service = i_services[route.service.id]
    if not service then
      return nil, "could not find internal service for internal route"
    end

    -- ensure route defaults are set
    route.created_at = route.created_at or internal_route_index
    route.strip_path = route.strip_path or true
    route.preserve_host = route.preserve_host or false
    route.regex_priority = route.regex_priority or 0
    route.protocols = route.protocols or { "http", "https" }

    -- ensure service defaults are set
    service.host = service.host or "0.0.0.0"
    service.created_at = service.created_at or internal_route_index + 1
    service.protocol = service.protocol or "http"
    service.retries = service.retries or 5
    service.read_timeout = service.read_timeout or 60000
    service.write_timeout = service.write_timeout or 60000
    service.connect_timeout = service.connect_timeout or 60000

    -- push internal route onto routes table
    i = i + 1
    routes[i] = {
      route = route,
      service = service,
    }
  end
end


function _M:get_plugin_config(conf)
  local plugins = self.config.plugins
  for i = 1, #plugins do
    local plugin = plugins[i]

    if   conf.plugin_name == plugin.name
    and     conf.route_id == plugin.route_id
    and   conf.service_id == plugin.service_id
    and  conf.consumer_id == plugin.consumer_id
    and       conf.api_id == plugin.api_id then
      local cfg       = plugin.config or {}

      cfg.api_id      = plugin.api_id
      cfg.route_id    = plugin.route_id
      cfg.service_id  = plugin.service_id
      cfg.consumer_id = plugin.consumer_id

      return cfg
    end
  end
end


function _M:add_internal_plugins(plugins, map)
  local kong_config = singletons.configuration
  if not kong_config.proxy_listen then
    ngx.log(ngx.DEBUG, "not adding internal plugins to enabled listing, ",
                      "because proxy is disabled")
    return
  end

  local internal_plugins = self.config.plugins
  for i = 1, #internal_plugins do
    local plugin = internal_plugins[i]
    if not map[plugin.name] then
      plugins[#plugins+1] = plugin.name
    end
    map[plugin.name] = true
  end
end


function _M:filter_plugins(service_id, ctx_plugins)
  if not service_id then
    return ctx_plugins
  end

  if service_id and self:has_service(service_id) then
    local plugins = {}
    for key, config in pairs(ctx_plugins) do
      if config.service_id == service_id then
        plugins[key] = config
      end
    end
    return plugins
  end

  return ctx_plugins
end


return _M
