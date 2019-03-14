local lapis        = require "lapis"
local api_helpers  = require "kong.api.api_helpers"
local app_helpers  = require "lapis.application"
local singletons   = require "kong.singletons"
local responses    = require "kong.tools.responses"
local workspaces   = require "kong.workspaces"
local ee_api       = require "kong.enterprise_edition.api_helpers"
local ws_helper    = require "kong.workspaces.helper"

local log = ngx.log
local ERR = ngx.ERR

local fmt = string.format
local _M = {}


_M.app = lapis.Application()


_M.app:before_filter(function(self)
  local invoke_plugin = singletons.invoke_plugin
  local ctx = ngx.ctx

  -- in case of endpoint with missing `/`, this block is executed twice.
  -- So previous workspace should be dropped
  ctx.admin_api_request = true
  ctx.workspaces = nil
  ngx.ctx.rbac = nil

  local ws_name = self.params.workspace_name or workspaces.DEFAULT_WORKSPACE

  local workspace, err = workspaces.fetch_workspace(ws_name)
  if err then
    ngx.log(ngx.ERR, err)
    return responses.send_HTTP_INTERNAL_SERVER_ERROR()
  end

  if not workspace then
    return responses.send_HTTP_NOT_FOUND(fmt("Workspace '%s' not found", ws_name))
  end

  -- save workspace name in the context; if not passed, default workspace is
  -- 'default'
  ctx.workspaces = { workspace }
  self.params.workspace_name = nil

  local cors_conf = {
    origins = ws_helper.build_ws_portal_cors_origins(workspace),
    methods = { "GET", "PUT", "PATCH", "DELETE", "POST" },
    credentials = true,
  }

  local ok, err = invoke_plugin({
    name = "cors",
    config = cors_conf,
    phases = { "access", "header_filter"},
    api_type = ee_api.apis.PORTAL,
    db = singletons.dao.db.new_db,
  })

  if not ok then
    log(ERR, err)
    return responses.send_HTTP_INTERNAL_SERVER_ERROR()
  end

  api_helpers.filter_body_content_type(self)
end)


-- Register application defaults
_M.app.handle_404 = function(self)
  return responses.send_HTTP_NOT_FOUND()
end


_M.app.handle_error = function(self, err, trace)
  if err and string.find(err, "don't know how to respond to", nil, true) then
    return responses.send_HTTP_METHOD_NOT_ALLOWED()
  end

  ngx.log(ngx.ERR, err, "\n", trace)

  -- We just logged the error so no need to give it to responses and log it
  -- twice
  return responses.send_HTTP_INTERNAL_SERVER_ERROR()
end


function _M.on_error(self)
  local err = self.errors[1]

  if type(err) ~= "table" then
    return responses.send_HTTP_INTERNAL_SERVER_ERROR(tostring(err))
  end

  if err.db then
    return responses.send_HTTP_INTERNAL_SERVER_ERROR(err.message)
  end

  if err.unique then
    return responses.send_HTTP_CONFLICT(err.tbl)
  end

  if err.foreign then
    return responses.send_HTTP_NOT_FOUND(err.tbl)
  end

  return responses.send_HTTP_BAD_REQUEST(err.tbl or err.message)
end


-- Instantiate a single helper object for wrapped methods
local handler_helpers = {
  responses = responses,
  yield_error = app_helpers.yield_error
}


function _M.attach_routes(routes, app)
  for route_path, methods in pairs(routes) do
    methods.on_error = methods.on_error or _M.on_error

    methods.resource = nil

    for method_name, method_handler in pairs(methods) do
      local wrapped_handler = function(self)
        return method_handler(self, singletons.dao, handler_helpers)
      end

      methods[method_name] = api_helpers.parse_params(wrapped_handler)
    end

    app:match(route_path, route_path, app_helpers.respond_to(methods))
    app:match("workspace_" .. route_path, "/:workspace_name" .. route_path,
              app_helpers.respond_to(methods))
  end
end

-- Load core routes
for _, v in ipairs({"api"}) do
  local routes = require("kong.portal." .. v)
  _M.attach_routes(routes, _M.app)
end


return _M
