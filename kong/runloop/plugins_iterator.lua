local kong         = kong
local setmetatable = setmetatable

local ok, new_tab = pcall(require, "table.new")
if not ok then
  new_tab = function (narr, nrec) return {} end
end

-- Given a key, retrieve a plugin from the cache
-- @treturn table Plugin retrieved from the cache
-- @treturn string|nil err Error message if needed
-- @treturn boolean true if we should stop looking at the cache and query the db instead
local function probe_cache_for_plugin(key)
  local _, err, plugin = kong.cache:probe(key)
  if err then
    return nil, err, nil
  end

  if not plugin then
    return nil, nil, true -- not found in cache, must query db to handle recent additions to db
  end

  if not plugin.enabled then
    return nil, nil, nil -- found in cache but disabled. try with other keys
  end

  if plugin.run_on ~= "all" then
    if ngx.ctx.is_service_mesh_request then
      if plugin.run_on == "first" then
        return nil, nil, nil -- found in cache but incompatible. try with other keys
      end

    else
      if plugin.run_on == "second" then
        return nil, nil, nil -- found in cache but incompatible. try with other keys
      end
    end
  end

  return plugin, nil, nil
end


-- Combines the given parameters in several different keys, trying them on the cache
-- This function does not use get_keys_for_plugin on purpose, to avoid table allocations
-- @treturn table Plugin retrieved from the cache
-- @treturn string|nil err Error message if needed
-- @treturn boolean true if we should stop looking at the cache and query the db instead
local function get_plugin_from_cache(plugin_name, route_id, service_id, consumer_id)
  local key, plugin, err, query_db
  local dao = kong.db.plugins
  local get_cache_key = dao.cache_key

  if route_id and service_id and consumer_id then
    key = get_cache_key(dao, plugin_name, route_id, service_id, consumer_id)
    plugin, err, query_db = probe_cache_for_plugin(key)
    if plugin or err or query_db then
      return plugin, err, query_db
    end
  end

  if route_id and consumer_id then
    key = get_cache_key(dao, plugin_name, route_id, nil, consumer_id)
    plugin, err, query_db = probe_cache_for_plugin(key)
    if plugin or err or query_db then
      return plugin, err, query_db
    end
  end

  if service_id and consumer_id then
    key = get_cache_key(dao, plugin_name, nil, service_id, consumer_id)
    plugin, err, query_db = probe_cache_for_plugin(key)
    if plugin or err or query_db then
      return plugin, err, query_db
    end
  end

  if route_id and service_id then
    key = get_cache_key(dao, plugin_name, route_id, service_id, nil)
    plugin, err, query_db = probe_cache_for_plugin(key)
    if plugin or err or query_db then
      return plugin, err, query_db
    end
  end

  if consumer_id then
    key = get_cache_key(dao, plugin_name, nil, nil, consumer_id)
    plugin, err, query_db = probe_cache_for_plugin(key)
    if plugin or err or query_db then
      return plugin, err, query_db
    end
  end

  if route_id then
    key = get_cache_key(dao, plugin_name, route_id, nil, nil)
    plugin, err, query_db = probe_cache_for_plugin(key)
    if plugin or err or query_db then
      return plugin, err, query_db
    end
  end

  if service_id then
    key = get_cache_key(dao, plugin_name, nil, service_id, nil)
    plugin, err, query_db = probe_cache_for_plugin(key)
    if plugin or err or query_db then
      return plugin, err, query_db
    end
  end

end


-- With the given params, return a list of all the keys that would be tested
-- for those params, in order. This list will be used to load all the plugins
-- from the database and fill up the negatives in one go
local function get_keys_for_plugin(plugin_name, route_id, service_id, consumer_id)
  local keys = new_tab(8, 0)
  local len = 0

  local dao = kong.db.plugins
  local get_cache_key = dao.cache_key

  if route_id and service_id and consumer_id then
    len = len + 1
    keys[len] = get_cache_key(dao, plugin_name, route_id, service_id, consumer_id)
  end

  if route_id and consumer_id then
    len = len + 1
    keys[len] = get_cache_key(dao, plugin_name, route_id, nil, consumer_id)
  end

  if service_id and consumer_id then
    len = len + 1
    keys[len] = get_cache_key(dao, plugin_name, nil, service_id, consumer_id)
  end

  if route_id and service_id then
    len = len + 1
    keys[len] = get_cache_key(dao, plugin_name, route_id, service_id, nil)
  end

  if consumer_id then
    len = len + 1
    keys[len] = get_cache_key(dao, plugin_name, nil, nil, consumer_id)
  end

  if route_id then
    len = len + 1
    keys[len] = get_cache_key(dao, plugin_name, route_id, nil, nil)
  end

  if service_id then
    len = len + 1
    keys[len] = get_cache_key(dao, plugin_name, nil, service_id, nil)
  end

  len = len + 1
  keys[len] = get_cache_key(dao, plugin_name, nil, nil, nil)

  return keys
end


-- Fills up the cache using `get_bulk` for paralell access, filling up positive and negative hits
local function populate_cache(keys, plugins)
  local plugins_len = #plugins

  local dict = new_tab(0, plugins_len)
  local plugin
  for i = 1, plugins_len do
    plugin = plugins[i]
    if plugin.cache_key then
      dict[plugin.cache_key] = plugin
    end
  end

  local find_in_dict = function(key)
    return dict[key]
  end

  local cache = kong.cache
  local cache_get = cache.get
  local ok, err
  for i = 1, #keys do
    ok, err = cache_get(cache, keys[i], nil, find_in_dict)
    if not ok then
      return nil, err
    end
  end

  return true
end


local function handle_error(err)
  ngx.ctx.delay_response = false
  ngx.log(ngx.ERR, tostring(err))
  return ngx.exit(ngx.ERROR)
end


local function get_next(self)
  local i = self.i + 1

  local plugin = self.loaded_plugins[i]
  if not plugin then
    return nil
  end

  self.i = i

  if not self.configured_plugins[plugin.name] then
    return get_next(self)
  end

  local ctx = self.ctx

  -- load the plugin configuration in early phases
  if self.access_or_cert_ctx then

    local route        = self.route
    local service      = self.service
    local consumer     = ctx.authenticated_consumer

    if route and plugin.no_route then
      route = nil
    end
    if service and plugin.no_service then
      service = nil
    end
    if consumer and plugin.no_consumer then
      consumer = nil
    end

    local    route_id = route    and    route.id or nil
    local  service_id = service  and  service.id or nil
    local consumer_id = consumer and consumer.id or nil

    local plugin_name = plugin.name

    local plugin, err, query_db = get_plugin_from_cache(plugin_name,
                                                        route_id,
                                                        service_id,
                                                        consumer_id)
    if err then
      return handle_error(err)
    end

    if not plugin and query_db then
      local keys = get_keys_for_plugin(plugin_name, route_id, service_id, consumer_id)
      local plugins, err = kong.db.plugins:select_by_cache_keys(keys)

      if err then
        return handle_error(err)
      end

      local _, err = populate_cache(keys, plugins)
      if err then
        return handle_error(err)
      end

      plugin = plugins[1]
    end

    if plugin then
      local cfg = plugin.config or {}

      cfg.route_id    = type(plugin.route) == "table" and plugin.route.id
      cfg.service_id  = type(plugin.service) == "table" and plugin.service.id
      cfg.consumer_id = type(plugin.consumer) == "table" and plugin.consumer.id

      ctx.plugins_for_request[plugin.name] = cfg
    end
  end

  -- return the plugin configuration
  local plugins_for_request = ctx.plugins_for_request
  if plugins_for_request[plugin.name] then
    return plugin, plugins_for_request[plugin.name]
  end

  return get_next(self) -- Load next plugin
end


local plugin_iter_mt = { __call = get_next }


--- Plugins for request iterator.
-- Iterate over the plugin loaded for a request, stored in
-- `ngx.ctx.plugins_for_request`.
-- @param[type=boolean] access_or_cert_ctx Tells if the context
-- is access_by_lua_block. We don't use `ngx.get_phase()` simply because we can
-- avoid it.
-- @treturn function iterator
local function iter_plugins_for_req(ctx, loaded_plugins, configured_plugins,
                                    access_or_cert_ctx)
  if not ctx.plugins_for_request then
    ctx.plugins_for_request = {}
  end

  local plugin_iter_state = {
    i                     = 0,
    ctx                   = ctx,
    route                 = ctx.route,
    service               = ctx.service,
    loaded_plugins        = loaded_plugins,
    configured_plugins    = configured_plugins,
    access_or_cert_ctx    = access_or_cert_ctx,
  }

  return setmetatable(plugin_iter_state, plugin_iter_mt)
end


return iter_plugins_for_req
