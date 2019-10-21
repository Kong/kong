local TTL_FOREVER = { ttl = 0 }

local _M = {}

local kong = kong
local ipairs = ipairs


local function load_routes_from_db(db, route_id)
  local routes, err = db.routes:select(route_id)
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


local function get_snis_for_plugin(db, plugin, snis)
  -- plugin applied on service
  local service_pk = plugin.service
  if service_pk then
    for route, err in db.routes:each_for_service(service_pk) do
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
                                      routes_pk)

    if err then
      return err
    end

    if not build_snis_for_route(route, snis) then
      snis["*"] = true
    end

    return
  end

  -- plugin applied on global scope
  snis["*"] = true
end


function _M.build_ssl_route_filter_set()
  local db = kong.db
  local snis = {}

  for plugin, err in db.plugins:each(1000) do
    if err then
      return nil, "could not load plugins: " .. err
    end

    if plugin.name == "mtls-auth" then
      local err = get_snis_for_plugin(db, plugin, snis)
      if err then
        return nil, err
      end

      if snis["*"] then
        break
      end
    end
  end

  return snis
end


return _M
