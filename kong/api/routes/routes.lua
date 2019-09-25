local singletons  = require "kong.singletons"
local reports     = require "kong.reports"
local utils       = require "kong.tools.utils"
local workspaces  = require "kong.workspaces"
local Router      = require "kong.router"
local core_handler = require "kong.runloop.handler"
local uuid = require("kong.tools.utils").uuid


local kong = kong
local null = ngx.null


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

    local rp1 = r1.regex_priority or 0
    local rp2 = r2.regex_priority or 0

    if rp1 == rp2 then
      return r1.created_at < r2.created_at
    end
    return rp1 > rp2
  end)

  local router, err = Router.new(routes)
  if not router then
    return nil, "could not create router: " .. err
  end

  return router
end


local function rebuild_routes(db)
  if kong.configuration.route_validation_strategy ~= 'off'  then
    local old_wss = ngx.ctx.workspaces
    ngx.ctx.workspaces = {}
    core_handler.build_router(db, uuid())
    ngx.ctx.workspaces = old_wss
  end
end


return {
  ["/routes"] = {
    POST = function(self, db, helpers, parent)
      rebuild_routes(db)

      local ok, err = workspaces.is_route_crud_allowed(self, singletons.router, true)
      if not ok then
        return kong.response.exit(err.code, {message = err.message})
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
      --todo change it to PUT, handle route collision
      rebuild_routes(db)
      return parent()
    end,
    DELETE = function(self, db, helpers, parent)
      rebuild_routes(db)
      return parent()
    end,

    PATCH = function(self, db, helpers, parent)
      -- create temporary router
      rebuild_routes(db)

      local old_workspaces = ngx.ctx.workspaces
      ngx.ctx.workspaces = {}
      local r = build_router_without(self.params.routes)
      ngx.ctx.workspaces = old_workspaces

      local ok, err = workspaces.is_route_crud_allowed(self, r)
      if not ok then
        return kong.response.exit(err.code, {message = err.message})
      end

      return parent()
    end
  },

  ["/routes/:routes/plugins"] = {
    POST = function(_, _, _, parent)
      return parent(post_process)
    end,
  },
}
