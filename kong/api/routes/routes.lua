local api_helpers = require "kong.api.api_helpers"
local singletons  = require "kong.singletons"
local responses   = require "kong.tools.responses"
local endpoints   = require "kong.api.endpoints"
local reports     = require "kong.core.reports"
local utils       = require "kong.tools.utils"
local crud        = require "kong.api.crud_helpers"
local workspaces  = require "kong.workspaces"
local Router      = require "kong.core.router"
local core_handler = require "kong.core.handler"
local uuid = require("kong.tools.utils").uuid


local tostring    = tostring
local type        = type

local function build_router_without(excluded_route)
  local routes, i = {}, 0
  local db = singletons.db
  local old_wss = ngx.ctx.workspaces
  ngx.ctx.workspaces = {}
  local routes_iterator = db.routes:each()

  local route, err = routes_iterator()
  while route do
    local service_pk = route.service

    if not service_pk then
      return nil, "route (" .. route.id .. ") is not associated with service"
    end

    local service

    -- TODO: db requests in loop, problem or not
    service, err = db.services:select(service_pk)
    if not service then
      return nil, "could not find service for route (" .. route.id .. "): " .. err
    end

    local r = {
      route   = route,
      service = service,
    }

    if route.hosts ~= null then
      -- TODO: headers should probably be moved to route
      r.headers = {
        host = route.hosts,
      }
    end

    i = i + 1
    if r.id ~= excluded_route then
      routes[i] = r
    end

    route, err = routes_iterator()
  end
  if err then
    return nil, "could not load routes: " .. err
  end

  -- inject internal proxies into the router
  local _, err = singletons.internal_proxies:build_routes(i, routes)
  if err then
    return nil, err
  end

  table.sort(routes, function(r1, r2)
    r1, r2 = r1.route, r2.route
    if r1.regex_priority == r2.regex_priority then
      return r1.created_at < r2.created_at
    end
    return r1.regex_priority > r2.regex_priority
  end)
  ngx.ctx.workspaces = old_wss

  local router, err = Router.new(routes)
  if not router then
    return nil, "could not create router: " .. err
  end

  return router
end

return {
  ["/routes"] = {
    before = function(self, db, helpers)
      local old_wss = ngx.ctx.workspaces
      ngx.ctx.workspaces = {}
      core_handler.build_router(db, uuid())
      ngx.ctx.workspaces = old_wss
    end,

    POST = function(self, _, _, parent)
      if workspaces.is_route_colliding(self, singletons.router) then
        local err = "API route collides with an existing API"
        return responses.send_HTTP_CONFLICT(err)
      end
      return parent()
    end
  },

  ["/routes/:routes"] = {
    before = function(self, db, helpers)
      local uuid = require("kong.tools.utils").uuid
      local old_wss = ngx.ctx.workspaces
      ngx.ctx.workspaces = {}
      core_handler.build_router(db, uuid())
      ngx.ctx.workspaces = old_wss
    end,

    PATCH = function(self, db, helpers, parent)
      -- create temporary router
      local r = build_router_without(self.params.routes)
      if workspaces.is_route_colliding(self, r) then
        local err = "API route collides with an existing API"
        return responses.send_HTTP_CONFLICT(err)
      end

      return parent()
    end
  },

  ["/routes/:routes/service"] = {
    PATCH = function(self, _, _, parent)
      api_helpers.resolve_url_params(self)
      return parent()
    end,
  },

  ["/routes/:routes/plugins"] = {
    on_error = function(self)
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
    end,

    before = function(self, db, helpers)
      local id = self.params.routes

      local parent_entity, _, err_t = db.routes:select({ id = id })
      if err_t then
        return endpoints.handle_error(err_t)
      end

      if not parent_entity then
        return helpers.responses.send_HTTP_NOT_FOUND()
      end

      self.params.routes   = nil
      self.params.route_id = parent_entity.id
    end,

    GET = function(self)
      crud.paginated_set(self, singletons.dao.plugins)
    end,

    POST = function(self)
      crud.post(self.params, singletons.dao.plugins,
        function(data)
          local r_data = utils.deep_copy(data)
          r_data.config = nil
          r_data.e = "r"
          reports.send("api", r_data)
        end
      )
    end,

    PUT = function(self)
      crud.put(self.params, singletons.dao.plugins)
    end
  },
}
