-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local route_collision = require "kong.enterprise_edition.workspaces.route_collision"
local Router = require "kong.router"
local singletons = require "kong.singletons"
local core_handler = require "kong.runloop.handler"
local uuid = require("kong.tools.utils").uuid


local kong = kong
local null = ngx.null
local GLOBAL_QUERY_OPTS = { workspace = null }


local function build_router_without(excluded_route)
  local routes, i = {}, 0
  local db = kong.db
  local routes_iterator = db.routes:each(nil, GLOBAL_QUERY_OPTS)

  local route, err = routes_iterator()
  while route do
    local service_pk = route.service

    if not service_pk then
      return nil, "route (" .. route.id .. ") is not associated with service"
    end

    local service

    -- TODO: db requests in loop, problem or not
    service, err = db.services:select(service_pk, GLOBAL_QUERY_OPTS)
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
  local _, err = kong.internal_proxies:build_routes(i, routes)
  if err then
    return nil, err
  end

  -- XXXCORE there are additional criteria for sorting routes nowadays
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
  if kong.configuration.route_validation_strategy == 'smart'  then
    core_handler.build_router(db, uuid())
  end
end


return {
  ["/routes"] = {
    POST = function(self, db, helpers, parent)
      rebuild_routes(db)

      local ok, err = route_collision.is_route_crud_allowed(self, singletons.router, true)
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
    PUT = function(self, db, helpers, parent)
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

      local r = build_router_without(self.params.routes)

      local ok, err = route_collision.is_route_crud_allowed(self, r)
      if not ok then
        return kong.response.exit(err.code, {message = err.message})
      end

      return parent()
    end
  },
}
