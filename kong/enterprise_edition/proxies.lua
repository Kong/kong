local singletons = require "kong.singletons"
local url = require "socket.url"


local _M = {}
local mt = { __index = _M }


_M.proxy_prefix = "_kong"


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


function _M:get_plugin_config(
  route_id,
  service_id,
  consumer_id,
  plugin_name,
  api_id)
  local plugins = self.config.plugins
  for i = 1, #plugins do
    local plugin = plugins[i]

    if   plugin_name == plugin.name
    and     route_id == plugin.route_id
    and   service_id == plugin.service_id
    and  consumer_id == plugin.consumer_id
    and       api_id == plugin.api_id then
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
