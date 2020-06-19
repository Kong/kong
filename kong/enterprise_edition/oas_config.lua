local singletons = require "kong.singletons"
local lyaml      = require "lyaml"
local cjson      = require "cjson.safe"
local pl_stringx = require "pl.stringx"
local pl_tablex  = require "pl.tablex"
local socket_url = require "socket.url"
local workspaces = require "kong.workspaces"

local yaml_load    = lyaml.load
local cjson_decode = cjson.decode
local sub          = string.sub
local gsub         = string.gsub
local to_lower     = string.lower
local to_upper     = string.upper
local match        = string.match
local insert       = table.insert
local pl_split     = pl_stringx.split
local pl_pairmap   = pl_tablex.pairmap
local tonumber     = tonumber

local core_handler = require "kong.runloop.handler"
local uuid         = require("kong.tools.utils").uuid


local _M = {}


local function rebuild_routes()
  local old_wss = ngx.ctx.workspaces
  ngx.ctx.workspaces = {}
  core_handler.build_router(singletons.db, uuid())
  ngx.ctx.workspaces = old_wss
end


function _M.post_auto_config(spec_str)
  -- convert from str to lua table
  local spec, err = _M.spec_str_to_table(spec_str)
  if err then
    return nil, { code = 400, message = err }
  end

  -- populate service config tables
  local service_configs, err = _M.get_service_configs(spec)
  if err then
    return nil, { code = 400, message = err }
  end

  -- create services
  local services, err = _M.create_services(service_configs)
  if err then
    return nil, err
  end

  -- create routes
  local routes, err = _M.create_routes(spec, services)
  if err then
    return nil, err
  end

  return {
    services = services,
    routes = routes,
  }
end


function _M.patch_auto_config(spec_str, recreate_routes)
  local resources_created = recreate_routes
  -- convert from str to lua table
  local spec, err = _M.spec_str_to_table(spec_str)
  if err then
    return nil, { code = 400, message = err }
  end

  -- populate service config tables
  local service_configs, err = _M.get_service_configs(spec)
  if err then
    return nil, { code = 400, message = err }
  end

  -- update services
  local ok, err, services, created_services = _M.update_services(service_configs)
  if not ok then
    return nil, err
  end

  -- recreate routes
  local routes
  if recreate_routes == true then
    local _, err = _M.delete_existing_routes(services)
    if err then
      return nil, err
    end

    rebuild_routes()

    routes, err = _M.create_routes(spec, services)
    if err then
      return nil, err
    end
  elseif #created_services > 0 then
    -- or create new routes for a new service
    routes, err = _M.create_routes(spec, created_services)
    if err then
      return nil, err
    end

    resources_created = true
  end

  return true, nil, {
    services = services,
    routes = routes,
  }, resources_created
end


function _M.delete_existing_routes(services)
  for _, service in ipairs(services) do
    for route, err in singletons.db.routes:each_for_service({ id = service.id }) do
      if err then
        return nil, err
      end

      local _, _, err_t = singletons.db.routes:delete({ id = route.id })
      if err_t then
        return nil, err_t
      end
    end
  end

  return true
end


function _M.update_services(service_configs)
  local services = {}
  local created_services = {}

  for _, service_config in ipairs(service_configs) do
    local service

    -- check for existing services with same name
    local existing_service, _, err_t = singletons.db.services:select_by_name(
                                                           service_config.name)
    if err_t then
      return nil, err_t
    end

    -- update if we have an existing one
    if existing_service then
      service, _, err_t = singletons.db.services:update({
        id = existing_service.id
      }, service_config)

      if err_t then
        return nil, err_t
      end
    else
      -- otherwise, create new service
      service, _, err_t = singletons.db.services:insert(service_config)
      if err_t then
        return nil, err_t
      end

      insert(created_services, service)
    end

    insert(services, service)
  end

  return true, nil, services, created_services
end


function _M.create_services(service_configs)
  local services = {}

  for _, service_config in ipairs(service_configs) do
    local service, _, err_t = singletons.db.services:insert(service_config)
    if err_t then
      return nil, err_t
    end

    insert(services, service)
  end

  return services
end


function _M.create_routes(spec, services)
  local routes = {}

  for path, methods in pairs(spec.paths) do
    local formatted_path = gsub(path, "{(.-)}", "(?<%1>\\S+)")

    for _, service in ipairs(services) do
      local route_conf = {
        params = {
          service = { id = service.id },
          paths = { formatted_path },
          protocols = { service.protocol },
          strip_path = false,
          methods = pl_pairmap(function(key)
            return to_upper(key)
          end, methods),
        },
      }

      local ok, err = workspaces.is_route_crud_allowed(route_conf, singletons.router)
      if not ok then
        return nil, err
      end


      local route, _, err_t = singletons.db.routes:insert(route_conf.params)
      if err_t then
        return nil, err_t
      end

      insert(routes, route)
    end
  end

  return routes
end


function _M.spec_str_to_table(spec_str)
  if type(spec_str) ~= "string" or spec_str == "" then
    return nil, "spec is required"
  end

  local table, ok

  -- first try to parse as JSON
  table = cjson_decode(spec_str)
  if not table then
    -- if fail, try as YAML
    ok, table = pcall(yaml_load, spec_str)
    if not ok then
      return nil, "Failed to convert spec to table " .. table
    end
  end

  return table
end


function _M.get_service_configs(spec)
  local configs = {}
  local host = spec.host

  local version = spec.openapi or spec.swagger
  if not version then
    return nil, "missing openapi or swagger version"
  end

  local major_version = match(version, "^(%d+)%.%d")
  if major_version ~= "2" and major_version ~= "3" then
    return nil, "unsupported major version: " .. major_version .. ". OAS major versions v2 and v3 supported"
  end

  if major_version == "2" then
    if type(host) ~= "string" or host == "" then
      return nil, "OAS v2 - host required"
    end

    local protocols = spec.schemes or { "https" }
    for _, protocol in ipairs(protocols) do
      if protocol == "http" or protocol == "https" then
        local config, err = _M.service_config_by_host(host, spec, protocol)
        if err then
          return nil, "OAS v2 - " .. err
        end

        insert(configs, config)
      end
    end
  end

  if major_version == "3" then
    local servers = spec.servers
    if not servers or next(servers) == nil then
      return nil, "OAS v3 - servers required"
    end

    -- counter table to help with naming of services
    local counters = {
      http = 0,
      https = 0
    }

    for i, server in ipairs(servers) do
      local config, err = _M.service_config_by_server(server, spec, counters)
      if err then
        return nil, "OAS v3 - " .. err
      end

      insert(configs, config)
    end
  end

  return configs
end


function _M.get_path(base_path)
  if not base_path or base_path == "" or base_path == "/" then
    return
  end

  local ok, first_char = pcall(sub, base_path, 1, 1)
  if not ok or first_char ~= "/" then
    return nil, "basePath must be a string with a leading `/` if provided"
  end

  return base_path
end


function _M.get_name(spec_info, protocol, index)
  spec_info = spec_info or {}

  local name = spec_info.title
  if not name or name == "" then
    return nil, "info.title is required for service name"
  end

  -- convert to lowercase and replace spaces with dashes
  -- add protocol and index suffixes
  local suffix = "-" .. index .. (protocol == "https" and "-secure" or "")
  return gsub(to_lower(name), "%s+", "-") .. suffix
end


function _M.service_config_by_host(host_and_port, spec, protocol)
  local host_parts = pl_split(host_and_port, ":")

  local name, err = _M.get_name(spec.info, protocol, 1)
  if err then
    return nil, err
  end

  local path, err = _M.get_path(spec.basePath)
  if err then
    return nil, err
  end

  return {
    name = name,
    protocol = protocol,
    host = host_parts[1],
    port = _M.get_port(host_parts[2], protocol),
    path = path,
  }
end


function _M.get_port(port, scheme)
  return tonumber(port) or port or
         (scheme == "http" and 80) or
         (scheme == "https" and 443) or nil
end


function _M.parse_url(url)
  if not url or url == "" then
    return nil, "url is required"
  end

  local parsed_url = socket_url.parse(url)

  return {
    protocol = parsed_url.scheme,
    host = parsed_url.host,
    port = _M.get_port(parsed_url.port, parsed_url.scheme),
    path = parsed_url.path,
  }
end

--[[
  TODO: Handle variable replacement in urls.
  This will change the return signature, this
  method will then return an array of configs
]]
function _M.service_config_by_server(server, spec, counters)
  local config, err = _M.parse_url(server.url)
  if err then
    return nil, err
  end

  -- increment counters (used in naming the services)
  counters[config.protocol] = counters[config.protocol] + 1

  local name, err = _M.get_name(spec.info, config.protocol, counters[config.protocol])
  if err then
    return nil, err
  end

  config.name = name

  return config
end


return _M
