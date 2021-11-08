-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local workspaces_iter
do
  local pok = pcall(require, "kong.workspaces")
  if not pok then
    -- no workspace support, that's fine
    workspaces_iter = function(_) return next, { default = {} }, nil end

  else
    workspaces_iter = function(db) return db.workspaces:each(1000) end
  end
end

local TTL_FOREVER = { ttl = 0 }

local _M = {}

local kong = kong
local ipairs = ipairs


local function load_routes_from_db(db, route_id, options)
  local routes, err = db.routes:select(route_id, options)
  if routes == nil then
    -- the third value means "do not cache"
    return nil, err, -1
  end

  return routes
end


local function build_snis_for_route(route, snis)
  if not route.snis or #route.snis == 0 then
    return false
  end

  for _, sni in ipairs(route.snis) do
    snis[sni] = true
  end

  return true
end


local function get_snis_for_plugin(db, plugin, snis, options)
  -- plugin applied on service
  local service_pk = plugin.service
  if service_pk then
    for route, err in db.routes:each_for_service(service_pk, nil, options) do
      if err then
        return err
      end

      -- every route should have SNI or ask cert on all requests
      if not build_snis_for_route(route, snis) then
        snis["*"] = true
        break
      end
    end

    return
  end

  -- plugin applied on route
  local routes_pk = plugin.route
  if routes_pk then
    local cache_key = db.routes:cache_key(routes_pk.id)
    local route, err = kong.cache:get(cache_key, TTL_FOREVER,
                                      load_routes_from_db, db,
                                      routes_pk, options)

    if err then
      return err
    end

    if not build_snis_for_route(route, snis, options) then
      snis["*"] = true
    end

    return
  end

  -- plugin applied on global scope
  snis["*"] = true
end

function _M.build_ssl_route_filter_set()
  kong.log.debug("building ssl route filter set")
  local db = kong.db
  local snis = {}

  local options = {}
  for workspace, err in workspaces_iter(db) do
    kong.log.debug("build filter for workspace ", workspace.name, " ", workspace.id)

    options.workspace = workspace.id
    for plugin, err in db.plugins:each(1000, options) do
      if err then
        return nil, "could not load plugins: " .. err
      end

      if plugin.enabled and plugin.name == "mtls-auth" then
        local err = get_snis_for_plugin(db, plugin, snis, options)
        if err then
          return nil, err
        end

        if snis["*"] then
          break
        end
      end
    end
  end

  return snis
end


return _M
