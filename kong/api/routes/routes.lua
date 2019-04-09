local api_helpers = require "kong.api.api_helpers"
local singletons  = require "kong.singletons"
local responses   = require "kong.tools.responses"
local reports     = require "kong.reports"
local utils       = require "kong.tools.utils"
local workspaces  = require "kong.workspaces"
local Router      = require "kong.router"
local core_handler = require "kong.runloop.handler"
local uuid = require("kong.tools.utils").uuid


local null        = ngx.null


local function post_process(data)
  local r_data = utils.deep_copy(data)
  r_data.config = nil
  r_data.e = "r"
  reports.send("api", r_data)
  return data
end


local function build_router_without(excluded_route)
  local routes, i = {}, 0
  local db = singletons.db
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

  local router, err = Router.new(routes)
  if not router then
    return nil, "could not create router: " .. err
  end

  return router
end


local function rebuild_routes(db)
  local old_wss = ngx.ctx.workspaces
  ngx.ctx.workspaces = {}
  core_handler.build_router(db, uuid())
  ngx.ctx.workspaces = old_wss
end


return {
  ["/routes"] = {
    POST = function(self, db, helpers, parent)
      rebuild_routes(db)

      if workspaces.is_route_colliding(self, singletons.router) then
        local err = "API route collides with an existing API"
        return responses.send_HTTP_CONFLICT(err)
      end
      return parent()
    end,
    GET = function(self, db, helpers, parent)
      rebuild_routes(db)
      return parent()
    end
  },

  ["/routes/:routes"] = {
    GET = function(self, db, helpers, parent)
      rebuild_routes(db)
      return parent()
    end,
    POST = function(self, db, helpers, parent)
      rebuild_routes(db)
      return parent()
    end,
    DELETE = function(self, db, helpers, parent)
      rebuild_routes(db)
      return parent()
    end,

    PATCH = function(self, db, helpers, parent)
      -- create temporary router
      local old_workspaces = ngx.ctx.workspaces
      ngx.ctx.workspaces = {}
      core_handler.build_router(db, uuid())
      local r = build_router_without(self.params.routes)
      ngx.ctx.workspaces = old_workspaces

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
    POST = function(_, _, _, parent)
      return parent(post_process)
    end,
  },
}
