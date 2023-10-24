-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local cjson = require "cjson"
local tablex = require "pl.tablex"
local workspaces = require "kong.workspaces"

local Router = require("lapis.router").Router

local arguments  = require "kong.api.arguments"
local meta = require "kong.meta"

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


-- XXX Look at how kong router is built, invalidated, etc
-- semaphores and stuff
function DeGraphQLHandler:init_worker()
  self:init_router()

  if kong.configuration.database == "off" or not (kong.worker_events and kong.worker_events.register) then
    return
  end

  kong.worker_events.register(function(data)
    workspaces.set_workspace(data.workspace)
    self:init_router()
  end, "crud", "degraphql_routes")
end


local function default_router()
  local router = Router()
  router.default_route = function()
    return kong.response.exit(404, { message = "Not Found" })
  end
  return router
end


-- XXX Look at how kong router is built, invalidated, etc
-- semaphores and stuff
function DeGraphQLHandler:init_router()

  local routers = {}

  for route, err in kong.db.degraphql_routes:each(1000) do
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

  return format(match[method], args), args
end


function DeGraphQLHandler:access(conf)

  if not self.router then
    self:init_router()
  end

  local query, variables = self:get_query()

  req_set_method("POST")
  ngx.var.upstream_uri = conf.graphql_server_path
  req_read_body()
  req_set_header("Content-Type", "application/json")
  req_set_body_data(cjson_encode({ query = query, variables = variables }))
end


return DeGraphQLHandler
