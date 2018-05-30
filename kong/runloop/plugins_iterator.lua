local responses    = require "kong.tools.responses"
local singletons   = require "kong.singletons"


local ipairs           = ipairs
local error            = error
local ngx_thread_spawn = ngx.thread.spawn
local ngx_thread_wait  = ngx.thread.wait
local new_tab
do
  local ok
  ok, new_tab = pcall(require, "table.new")
  if not ok then
    new_tab = function(narr, nrec) return {} end
  end
end


-- Loads a plugin config from the datastore.
-- @return plugin config table or an empty sentinel table in case of a db-miss
local function load_plugin_into_memory(route_id,
                                       service_id,
                                       consumer_id,
                                       plugin_name,
                                       api_id)
  local rows, err = singletons.dao.plugins:find_all {
             name = plugin_name,
         route_id = route_id,
       service_id = service_id,
      consumer_id = consumer_id,
           api_id = api_id,
  }
  if err then
    error(err)
  end

  if #rows > 0 then
    for _, row in ipairs(rows) do
      if    route_id == row.route_id    and
          service_id == row.service_id  and
         consumer_id == row.consumer_id and
              api_id == row.api_id      then
        return row
      end
    end
  end
  -- insert a cached value to not trigger too many DB queries.
  return { null = true }  -- works because: `.enabled == nil`
end


--- Load the configuration for a plugin entry in the DB.
-- Given an API, a Consumer and a plugin name, retrieve the plugin's
-- configuration if it exists. Results are cached in ngx.dict
-- @param[type=string] plugin_name Name of the plugin being tested for.
-- @param[type=string] route_id ID of the route being proxied.
-- @param[type=string] service_id ID of the service being proxied.
-- @param[type=string] consumer_id ID of the Consumer making the request (if any).
-- @param[type=string] api_id ID of the API being proxied.
-- @return table Plugin retrieved from the cache or database.
local function load_plugin_configuration(plugin_name,
                                         route_id,
                                         service_id,
                                         consumer_id,
                                         api_id)
  local plugin_cache_key = singletons.dao.plugins:cache_key(plugin_name,
                                                            route_id,
                                                            service_id,
                                                            consumer_id,
                                                            api_id)

  local plugin, err = singletons.cache:get(plugin_cache_key,
                                           nil,
                                           load_plugin_into_memory,
                                           route_id,
                                           service_id,
                                           consumer_id,
                                           plugin_name,
                                           api_id)
  if err then
    return nil, err -- forward error out of the coroutine
  end

  if plugin ~= nil and plugin.enabled then
    local cfg       = plugin.config or {}
    cfg.api_id      = plugin.api_id
    cfg.route_id    = plugin.route_id
    cfg.service_id  = plugin.service_id
    cfg.consumer_id = plugin.consumer_id

    return cfg
  end
end


local function load_one_plugin(self, plugin)
  local ctx = self.ctx

  local api          = self.api
  local route        = self.route
  local service      = self.service
  local consumer     = ctx.authenticated_consumer

  if consumer then
    local schema = plugin.schema
    if schema and schema.no_consumer then
      consumer = nil
    end
  end

  local      api_id = api      and      api.id or nil
  local    route_id = route    and    route.id or nil
  local  service_id = service  and  service.id or nil
  local consumer_id = consumer and consumer.id or nil

  local plugin_name = plugin.name
  local threads = new_tab(0, 9)
  local len = 0

  if route_id and service_id and consumer_id then
    len = len + 1
    threads[len] = ngx_thread_spawn(load_plugin_configuration, plugin_name,
                                    route_id, service_id, consumer_id, nil)
  end

  if route_id and consumer_id then
    len = len + 1
    threads[len] = ngx_thread_spawn(load_plugin_configuration, plugin_name,
                                    route_id, nil, consumer_id, nil)
  end

  if service_id and consumer_id then
    len = len + 1
    threads[len] = ngx_thread_spawn(load_plugin_configuration, plugin_name,
                                    nil, service_id, consumer_id, nil)
  end

  if api_id and consumer_id then
    len = len + 1
    threads[len] = ngx_thread_spawn(load_plugin_configuration, plugin_name,
                                    nil, nil, consumer_id, api_id)
  end

  if route_id and service_id then
    len = len + 1
    threads[len] = ngx_thread_spawn(load_plugin_configuration, plugin_name,
                                    route_id, service_id, nil, nil)
  end

  if consumer_id then
    len = len + 1
    threads[len] = ngx_thread_spawn(load_plugin_configuration, plugin_name,
                                    nil, nil, consumer_id, nil)
  end

  if route_id then
    len = len + 1
    threads[len] = ngx_thread_spawn(load_plugin_configuration, plugin_name,
                                    route_id, nil, nil, nil)
  end

  if service_id then
    len = len + 1
    threads[len] = ngx_thread_spawn(load_plugin_configuration, plugin_name,
                                    nil, service_id, nil, nil)
  end

  if api_id then
    len = len + 1
    threads[len] = ngx_thread_spawn(load_plugin_configuration, plugin_name,
                                    nil, nil, nil, api_id)
  end

  for i = 1, len do
    local _, cfg, err = assert(ngx_thread_wait(threads[i]))
    if err then
      ngx.ctx.delay_response = false
      return responses.send_HTTP_INTERNAL_SERVER_ERROR(err)
    end

    if cfg then
      return cfg
    end
  end

  -- perform the most expensive query last, only if needed
  -- TODO this needs real perf testing to see when it helps.
  -- Right now it penalizes every single request with global plugins enabled,
  -- but also uses less CPU. Since we cache negative results inside
  -- load_plugin_configuration, that could negate the gains
  local cfg, err = load_plugin_configuration(plugin_name, nil, nil, nil, nil)
  if err then
    ngx.ctx.delay_response = false
    return responses.send_HTTP_INTERNAL_SERVER_ERROR(err)
  end

  return cfg
end


local function get_next(self)
  local i = self.i
  local plugin = self.loaded_plugins[i]
  if not plugin then
    return nil
  end
  self.i = i + 1

  local plugin_conf

  if self.access_or_cert_ctx then
    -- load the plugin configuration in early phases and put it in ngx.ctx
    plugin_conf = load_one_plugin(self, plugin)
    self.ctx.plugins_for_request[plugin.name] = plugin_conf
  else
    -- in late phases, get the conf from ngx.ctx
    plugin_conf = self.ctx.plugins_for_request[plugin.name]
  end

  if plugin_conf then
    return plugin, plugin_conf
  end

  -- no plugin configuration, skip to the next one
  return get_next(self)
end


--- Plugins for request iterator.
-- Iterate over the plugin loaded for a request, stored in
-- `ngx.ctx.plugins_for_request`.
-- @param[type=boolean] access_or_cert_ctx Tells if the context
-- is access_by_lua_block. We don't use `ngx.get_phase()` simply because we can
-- avoid it.
-- @treturn function iterator
local function iter_plugins_for_req(loaded_plugins, access_or_cert_ctx)
  local ctx = ngx.ctx

  if not ctx.plugins_for_request then
    ctx.plugins_for_request = {}
  end

  local plugin_iter_state = {
    i                     = 1,
    ctx                   = ctx,
    api                   = ctx.api,
    route                 = ctx.route,
    service               = ctx.service,
    loaded_plugins        = loaded_plugins,
    access_or_cert_ctx    = access_or_cert_ctx,
  }

  return get_next, plugin_iter_state
end


return iter_plugins_for_req
