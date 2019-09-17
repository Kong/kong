local cjson = require "cjson"
local tablex = require "pl.tablex"

local Router = require("lapis.router").Router

local arguments  = require "kong.api.arguments"
local BasePlugin = require "kong.plugins.base_plugin"

local PLUGIN_NAME    = require("kong.plugins.degraphql").PLUGIN_NAME
local PLUGIN_VERSION = require("kong.plugins.degraphql").PLUGIN_VERSION

local _M = BasePlugin:extend()

local pairs = pairs
local string_gsub = string.gsub
local cjson_encode = cjson.encode
local load_arguments = arguments.load
local tx_union = tablex.union

-- XXX Trim down, tomorrow
local req_get_uri_args = ngx.req.get_uri_args
local req_set_header = ngx.req.set_header
local req_get_headers = ngx.req.get_headers
local req_get_method = ngx.req.get_method
local req_read_body = ngx.req.read_body
local req_set_body_data = ngx.req.set_body_data
local req_get_body_data = ngx.req.get_body_data
local req_clear_header = ngx.req.clear_header
local req_set_method = kong.service.request.set_method
local encode_args = ngx.encode_args
local ngx_decode_args = ngx.decode_args

local kong = kong


function format(text, args)
  return string_gsub(text, "({{([^}]+)}})", function(whole, match)
    return args[match] or ""
  end)
end


function _M:new()
  _M.super.new(self, PLUGIN_NAME)
end


-- XXX Look at how kong router is built, invalidated, etc
-- semaphores and stuff
function _M:init_worker()
  _M.super.init_worker(self)
  self:init_router()
  kong.worker_events.register(function(data)
    self:init_router()
  end, "crud", "degraphql_routes")
end


function default_router()
  local router = Router()
  router.default_route = function()
    return kong.response.exit(404, { message = "Not Found" })
  end
  return router
end


-- XXX Look at how kong router is built, invalidated, etc
-- semaphores and stuff
function _M:init_router()

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


function _M:get_query()
  local service_id = ngx.ctx.service.id

  if not self.routers[service_id] then
    return kong.response.exit(404, { message = "Not Found" })
  end

  -- At the moment, we only match based on method and uri
  -- args.uri and args.post get merged into uri args that can be used for
  -- templating the graphql query
  local uri        = ngx.var.upstream_uri
  local headers    = req_get_headers()
  local method     = req_get_method()
  local _args      = load_arguments()

  local args = tx_union(_args.uri, _args.post)

  local match, auto_args = self.routers[service_id]:resolve(uri)

  args = tx_union(args, auto_args)

  return format(match[method], args), args
end


function _M:access(conf)
  _M.super.access(self)

  if not self.router then
    self:init_router()
  end

  local query, variables = self:get_query()

  req_set_method("POST")
  ngx.var.upstream_uri = "/graphql"
  req_read_body()
  req_set_header("Content-Type", "application/json")
  req_set_body_data(cjson_encode({ query = query, variables = variables }))
end


function _M:header_filter(conf)
  _M.super.header_filter(self)
  -- anything we want to affect response headers?
  -- ngx.header["Bye-World"] = "this is on the response"
end


function _M:body_filter(conf)
  _M.super.body_filter(self)
  -- Do something with the body, if we wanted?
end


_M.PRIORITY = 1005
_M.VERSION = PLUGIN_VERSION

return _M
