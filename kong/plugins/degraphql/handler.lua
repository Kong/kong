-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local cjson = require "cjson"
local tablex = require "pl.tablex"
local graphql_parse = require "kong.gql.query.build_ast.parse"

local Router = require("lapis.router").Router

local arguments  = require "kong.api.arguments"
local meta = require "kong.meta"
local workspaces = require "kong.workspaces"

local type = type
local ipairs = ipairs

local FORCE = true

local DeGraphQLHandler = {
  PRIORITY = 1500,
  VERSION = meta.core_version
}

local string_gsub = string.gsub
local cjson_encode = cjson.encode
local load_arguments = arguments.load
local tx_union = tablex.union

local req_set_header = ngx.req.set_header
local req_get_method = ngx.req.get_method
local req_read_body = ngx.req.read_body
local req_set_body_data = ngx.req.set_body_data
local req_set_method = kong.service.request.set_method

local kong = kong


local function format(text, args)
  return string_gsub(text, "({{([^}]+)}})", function(whole, match)
    return args[match] or ""
  end)
end


local function default_router()
  local router = Router()
  router.default_route = function()
    return kong.response.exit(404, { message = "Not Found" })
  end
  return router
end


function DeGraphQLHandler:router_is_empty()
  return not self.routers or (type(self.routers) == "table" and tablex.size(self.routers) == 0)
end


function DeGraphQLHandler:update_router(force)
  local force = (not not force) or false

  -- Early exit when router is not empty and not forced
  if not force and not self:router_is_empty() then
    return
  end

  local routers = {}

  for route, err in kong.db.degraphql_routes:each(1000) do
    if err then
      kong.log.err("Degraphql plugin could not load routes: ", err)
      -- Break when error and try again on the next update_router
      break
    end

    if not routers[route.service.id] then
      routers[route.service.id] = default_router()
      Router()
    end

    routers[route.service.id]:add_route(route.uri, function(args)
      local r = {}
      for _, method in ipairs(route.methods) do
        r[method] = route.query
      end

      return r, args
    end)
  end

  self.routers = routers
end


local function coerce_query_variable(query_str, args)
  local parse_tree, err = graphql_parse(query_str)
  if not parse_tree then
    kong.log.err("Error parsing graphql query: ", err)
    return
  end

  local variable_definition = parse_tree.definitions and parse_tree.definitions[1]
                              and parse_tree.definitions[1].variableDefinitions

  if variable_definition and type(variable_definition) == "table" then
    for _, variable in ipairs(variable_definition) do
      local var_kind = variable.type.kind
      local var_type
      if var_kind == "listType" or  var_kind == "nonNullType" then
        var_type = variable.type.type.name.value
      end

      if var_kind == "namedType" then
        var_type = variable.type.name.value
      end

      if not var_type then
        kong.log.err("unsupported variable type: ", var_kind)
        return
      end

      local var_name = variable.variable.name.value
      local var_value = args[var_name]

      if var_value then
        if var_type == "Int" then
          args[var_name] = tonumber(var_value)
        elseif var_type == "Boolean" then
          args[var_name] = (var_value == "true")
        elseif var_type == "Float" then
          args[var_name] = tonumber(var_value)
        end
      end
    end
  end
end


function DeGraphQLHandler:get_query()
  local service_id = ngx.ctx.service.id

  if not self.routers[service_id] then
    return kong.response.exit(404, { message = "Not Found" })
  end

  -- At the moment, we only match based on method and uri
  -- args.uri and args.post get merged into uri args that can be used for
  -- templating the graphql query
  local uri        = ngx.var.upstream_uri
  local method     = req_get_method()
  local _args      = load_arguments()

  local args = tx_union(_args.uri, _args.post)

  local match, auto_args = self.routers[service_id]:resolve(uri)

  args = tx_union(args, auto_args)

  local query_str = match[method]
  coerce_query_variable(query_str, args)
  return format(query_str, args), args
end


function DeGraphQLHandler:init_worker()
  if not (kong.worker_events and kong.worker_events.register) then
    return
  end

  if kong.configuration.database == "off" then
    kong.worker_events.register(function(data)
      self:update_router(FORCE)
    end, "declarative", "reconfigure")
    return
  end

  kong.worker_events.register(function(data)
    workspaces.set_workspace(data.workspace)
    self:update_router(true)
  end, "crud", "degraphql_routes")
end


function DeGraphQLHandler:configure(conf)
  -- Force rebuild router in init_worker or config update
  self:update_router(FORCE)
end


function DeGraphQLHandler:access(conf)
  self:update_router()

  local query, variables = self:get_query()

  req_set_method("POST")
  ngx.var.upstream_uri = conf.graphql_server_path
  req_read_body()
  req_set_header("Content-Type", "application/json")
  req_set_body_data(cjson_encode({ query = query, variables = variables }))
end


return DeGraphQLHandler
