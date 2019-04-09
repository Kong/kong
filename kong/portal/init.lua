local lapis = require "lapis"
local utils = require "kong.tools.utils"
local tablex = require "pl.tablex"
local pl_pretty   = require "pl.pretty"
local api_helpers = require "kong.api.api_helpers"
local app_helpers = require "lapis.application"
local singletons = require "kong.singletons"
local responses = require "kong.tools.responses"
local workspaces = require "kong.workspaces"
local ee_api = require "kong.enterprise_edition.api_helpers"
local ws_helper = require "kong.workspaces.helper"
local constants = require "kong.constants"
local Errors = require "kong.db.errors"
local auth = require "kong.portal.auth"


local log = ngx.log
local ERR = ngx.ERR
local fmt = string.format
local sub = string.sub
local find = string.find


local PORTAL = constants.WORKSPACE_CONFIG.PORTAL
local PORTAL_AUTH = constants.WORKSPACE_CONFIG.PORTAL_AUTH


local app = lapis.Application()

-- auth not needed on these routes
local auth_whitelisted_uris = {
  ["/auth"] = true,
  ["/files/unauthenticated"] = true,
  ["/register"] = true,
  ["/validate-reset"] = true,
  ["/reset-password"] = true,
  ["/forgot-password"] = true,
}

-- only authenticate if authentication is enabled
local auth_conditional_uris = {
  ["/files"] = true,
}

local NEEDS_BODY = tablex.readonly({ PUT = 1, POST = 2, PATCH = 3 })


local function parse_params(fn)
  return app_helpers.json_params(function(self, ...)
    if NEEDS_BODY[ngx.req.get_method()] then
      local content_type = self.req.headers["content-type"]
      if content_type then
        content_type = content_type:lower()

        if find(content_type, "application/json", 1, true) and not self.json then
          return responses.send_HTTP_BAD_REQUEST("Cannot parse JSON body")

        elseif find(content_type, "application/x-www-form-urlencode", 1, true) then
          self.params = utils.decode_args(self.params)
        end
      end
    end

    self.params = api_helpers.normalize_nested_params(self.params)

    local res = fn(self, ...)
    if res == nil and ngx.status >= 200 then
      return ngx.exit(0)
    end

    return res
  end)
end


-- new DB
local function new_db_on_error(self)
  local err = self.errors[1]

  if type(err) ~= "table" then
    return responses.send_HTTP_INTERNAL_SERVER_ERROR(tostring(err))
  end

  if err.strategy then
    err.strategy = nil
  end

  if err.code == Errors.codes.SCHEMA_VIOLATION
  or err.code == Errors.codes.INVALID_PRIMARY_KEY
  or err.code == Errors.codes.FOREIGN_KEY_VIOLATION
  or err.code == Errors.codes.INVALID_OFFSET
  then
    return responses.send_HTTP_BAD_REQUEST(err)
  end

  if err.code == Errors.codes.NOT_FOUND then
    return responses.send_HTTP_NOT_FOUND(err)
  end

  if err.code == Errors.codes.PRIMARY_KEY_VIOLATION
  or err.code == Errors.codes.UNIQUE_VIOLATION
  then
    return responses.send_HTTP_CONFLICT(err)
  end

  return responses.send_HTTP_INTERNAL_SERVER_ERROR(err)
end


-- old DAO
local function on_error(self)
  local err = self.errors[1]

  if type(err) ~= "table" then
    return responses.send_HTTP_INTERNAL_SERVER_ERROR(tostring(err))
  end

  if err.forbidden then
    return responses.send_HTTP_FORBIDDEN(err.tbl)
  end

  if err.name then
    return new_db_on_error(self)
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


local function auth_required(uri, ws)
  -- whitelisted, no auth needed
  if auth_whitelisted_uris[uri] then
    return false
  end

  -- only check auth if auth is enabled
  if auth_conditional_uris[uri] then
    local portal_auth = ws_helper.retrieve_ws_config(PORTAL_AUTH, ws)
    return portal_auth and portal_auth ~= ""
  end

  return true
end


-- Register application defaults
app.handle_404 = function(self)
  return responses.send_HTTP_NOT_FOUND()
end


app.handle_error = function(self, err, trace)
  if err then
    if type(err) ~= "string" then
      err = pl_pretty.write(err)
    end
    if find(err, "don't know how to respond to", nil, true) then
      return responses.send_HTTP_METHOD_NOT_ALLOWED()
    end
  end

  ngx.log(ngx.ERR, err, "\n", trace)

  -- We just logged the error so no need to give it to responses and log it
  -- twice
  return responses.send_HTTP_INTERNAL_SERVER_ERROR()
end


-- Instantiate a single helper object for wrapped methods
local handler_helpers = {
  responses = responses,
  yield_error = app_helpers.yield_error
}


app:before_filter(function(self)
  local ctx = ngx.ctx

  -- in case of endpoint with missing `/`, this block is executed twice.
  -- So previous workspace should be dropped
  ctx.admin_api_request = true
  ctx.workspaces = nil
  ctx.rbac = nil

  local invoke_plugin = singletons.invoke_plugin
  local ws_name = self.params.workspace_name or workspaces.DEFAULT_WORKSPACE

  local ws, err = workspaces.fetch_workspace(ws_name)
  if err then
    ngx.log(ngx.ERR, err)
    return responses.send_HTTP_INTERNAL_SERVER_ERROR()
  end

  if not ws then
    return responses.send_HTTP_NOT_FOUND(fmt("'%s' workspace not found",
                                                                      ws_name))
  end

  -- check if portal is enabled
  local portal_enabled = ws_helper.retrieve_ws_config(PORTAL, ws)
  if not portal_enabled then
    return responses.send_HTTP_NOT_FOUND(fmt("'%s' portal disabled", ws_name))
  end

  -- save workspace name in the context; if not passed, default workspace is
  -- 'default'
  ctx.workspaces = { ws }
  self.params.workspace_name = nil

  local cors_conf = {
    origins = ws_helper.build_ws_portal_cors_origins(ws),
    methods = { "GET", "PUT", "PATCH", "DELETE", "POST" },
    credentials = true,
  }

  local ok, err = invoke_plugin({
    name = "cors",
    config = cors_conf,
    phases = { "access", "header_filter"},
    api_type = ee_api.apis.PORTAL,
    db = singletons.db,
  })

  if not ok then
    log(ERR, err)
    return responses.send_HTTP_INTERNAL_SERVER_ERROR()
  end

  if auth_required(ngx.var.uri, ws) then
    auth.authenticate_api_session(self, singletons.db, handler_helpers)
  end

  if not NEEDS_BODY[ngx.req.get_method()] then
    return
  end

  local content_type = self.req.headers["content-type"]
  if not content_type then
    local content_length = self.req.headers["content-length"]
    if content_length == "0" then
      return
    end

    if not content_length then
      local _, err = ngx.req.socket()
      if err == "no body" then
        return
      end
    end

  elseif sub(content_type, 1, 16) == "application/json"                  or
         sub(content_type, 1, 19) == "multipart/form-data"               or
         sub(content_type, 1, 33) == "application/x-www-form-urlencoded" then
    return
  end

  return responses.send_HTTP_UNSUPPORTED_MEDIA_TYPE()
end)


local function attach_routes(routes)
  for route_path, methods in pairs(routes) do
    methods.on_error = methods.on_error or on_error

    methods.resource = nil

    for method_name, method_handler in pairs(methods) do
      local wrapped_handler = function(self)
        return method_handler(self, singletons.db, handler_helpers)
      end

      methods[method_name] = parse_params(wrapped_handler)
    end

    app:match(route_path, route_path, app_helpers.respond_to(methods))
    app:match("workspace_" .. route_path, "/:workspace_name" .. route_path,
              app_helpers.respond_to(methods))
  end
end


-- Load core routes
for _, v in ipairs({"api"}) do
  local routes = require("kong.portal." .. v)
  attach_routes(routes)
end


return app
