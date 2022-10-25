-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local _M = {}

local kong = kong
local null = ngx.null
local ipairs = ipairs

local TTL_FOREVER = { ttl = 0 }

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

local function each_enabled_plugin(entity, plugin_name)
  local options = {
    -- show_ws_id = true,
    workspace = null,
    search_fields = {
      name = plugin_name,
      enabled = true
    }
  }

  local iter = entity:each(1000, options)
  local function iterator()
    local element, err = iter()
    if err then return nil, err end
    if element == nil then return end
    -- XXX
    -- `search_fields` is PostgreSQL-backed instances only.
    -- We also need a backstop here for Cassandra or DBless.
    if element.name == plugin_name and element.enabled then return element, nil end
    return iterator()
  end

  return iterator
end

function _M.build_ssl_route_filter_set(plugin_name)
  kong.log.debug("building ssl route filter set for plugin name " .. plugin_name)
  local db = kong.db
  local snis = {}

  local options = { workspace = null }
  for plugin, err in each_enabled_plugin(db.plugins, plugin_name) do
    if err then
      return nil, "could not load plugins: " .. err
    end

    local err = get_snis_for_plugin(db, plugin, snis, options)
    if err then
      return nil, err
    end

    if snis["*"] then
      break
    end
  end

  return snis
end


return _M
