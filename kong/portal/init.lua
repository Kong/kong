-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local lapis = require "lapis"
local utils = require "kong.tools.utils"
local tablex = require "pl.tablex"
local pl_pretty   = require "pl.pretty"
local api_helpers = require "kong.api.api_helpers"
local app_helpers = require "lapis.application"

local ee_api = require "kong.enterprise_edition.api_helpers"
local workspaces = require "kong.workspaces"
local Errors = require "kong.db.errors"
local crud_helpers = require "kong.portal.crud_helpers"
local workspace_config = require "kong.portal.workspace_config"
local portal_and_vitals_allowed = require "kong.enterprise_edition.license_helpers".portal_and_vitals_allowed


local kong = kong
local log = ngx.log
local ERR = ngx.ERR
local fmt = string.format
local sub = string.sub
local find = string.find
local unescape_uri = ngx.unescape_uri


local NEEDS_BODY = tablex.readonly({ PUT = 1, POST = 2, PATCH = 3 })


local app = lapis.Application()


local function parse_params(fn)
  return app_helpers.json_params(function(self, ...)
    if NEEDS_BODY[ngx.req.get_method()] then
      local content_type = self.req.headers["content-type"]
      if content_type then
        content_type = content_type:lower()

        if find(content_type, "application/json", 1, true) and not self.json then
          return kong.response.exit(400, { message = "Cannot parse JSON body"})

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
    return kong.response.exit(500, { message = tostring(err)})
  end

  if err.strategy then
    err.strategy = nil
  end

  if err.code == Errors.codes.SCHEMA_VIOLATION
  or err.code == Errors.codes.INVALID_PRIMARY_KEY
  or err.code == Errors.codes.FOREIGN_KEY_VIOLATION
  or err.code == Errors.codes.INVALID_OFFSET
  then
    return kong.response.exit(400, { message = err.message })
  end

  if err.code == Errors.codes.NOT_FOUND then
    return kong.response.exit(404, {message = "Not Found"})
  end

  if err.code == Errors.codes.PRIMARY_KEY_VIOLATION
  or err.code == Errors.codes.UNIQUE_VIOLATION
  then
    return kong.response.exit(409, { message = err.message })
  end


  ngx.log(ngx.ERR, err)
  return kong.response.exit(500, { message = "An unexpected error occurred" })
end


-- old DAO
local function on_error(self)
  local err = self.errors[1]

  if type(err) ~= "table" then
    return kong.response.exit(500, tostring(err))
  end

  if err.forbidden then
    return kong.response.exit(403, err.tbl)
  end

  if err.name then
    return new_db_on_error(self)
  end

  if err.db then
    ngx.log(ngx.ERR, err.message)

    return kong.response.exit(500, { message = "An unexpected error occurred" })
  end

  if err.unique then
    return kong.response.exit(409, { message = err.tbl.message })
  end

  if err.foreign then
    return kong.response.exit(404, { message = "Not found" })
  end

  return kong.response.exit(400, { message = err.tbl or err.message })
end


-- Register application defaults
app.handle_404 = function(self)
  return kong.response.exit(404, { message = "Not found" })
end


app.handle_error = function(self, err, trace)
  if err then
    if type(err) ~= "string" then
      err = pl_pretty.write(err)
    end
    if find(err, "don't know how to respond to", nil, true) then
      return kong.response.exit(405, { message = "Method not allowed"})
    end
  end

  ngx.log(ngx.ERR, err, "\n", trace)

  -- We just logged the error so no need to give it to responses and log it
  -- twice
  return kong.response.exit(500, { message = "An unexpected error occurred" })
end

-- api_helpers default route only allows redirects to valid app routes
app.default_route = api_helpers.default_route


-- Instantiate a single helper object for wrapped methods
local handler_helpers = {
  responses = {},
  yield_error = app_helpers.yield_error
}


app:before_filter(function(self)
  local ctx = ngx.ctx

  -- in case of endpoint with missing `/`, this block is executed twice.
  -- So previous workspace should be dropped
  ctx.admin_api_request = true
  ctx.workspace = nil
  ctx.rbac = nil

  local ws_name = workspaces.DEFAULT_WORKSPACE
  if self.params.workspace_name then
    ws_name = unescape_uri(self.params.workspace_name)
  end

  local ws, err = kong.db.workspaces:select_by_name(ws_name)
  if err then
    ngx.log(ngx.ERR, err)
    return kong.response.exit(500, { message = "An unexpected error occurred" })
  end

  if not ws then
    return kong.response.exit(404, { message = fmt("'%s' workspace not found", ws_name) })
  end

  -- save workspace name in the context; if not passed, default workspace is
  -- 'default'
  ctx.workspace = ws.id
  self.params.workspace_name = nil

  -- if portal is not enabled in both kong.conf and workspace, return 404
  crud_helpers.exit_if_portal_disabled()

  local ok, err = ee_api.set_cors_headers(
    workspace_config.build_ws_portal_cors_origins(ws),
    ee_api.apis.PORTAL)

  if not ok then
    log(ERR, err)
    return kong.response.exit(500, { message = "An unexpected error occurred" })
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

  return kong.response.exit(415)
end)


local function attach_routes(routes)
  for route_path, methods in pairs(routes) do
    methods.on_error = methods.on_error or on_error

    methods.resource = nil

    for method_name, method_handler in pairs(methods) do
      local wrapped_handler = function(self)
        return method_handler(self, kong.db, handler_helpers)
      end

      methods[method_name] = parse_params(wrapped_handler)
    end

    app:match(route_path, route_path, app_helpers.respond_to(methods))
    app:match("workspace_" .. route_path, "/:workspace_name" .. route_path,
              app_helpers.respond_to(methods))
  end
end

if portal_and_vitals_allowed() then
  -- Load core routes
  for _, v in ipairs({"api"}) do
    local routes = require("kong.portal." .. v)
    attach_routes(routes)
  end
end

return app
