-- Copyright (C) Kong Inc.

local BasePlugin   = require "kong.plugins.base_plugin"
local ratelimiting = require "kong.tools.public.rate-limiting"
local schema       = require "kong.plugins.rate-limiting-advanced.schema"
local event_hooks  = require "kong.enterprise_edition.event_hooks"


local kong     = kong
local max      = math.max
local tonumber = tonumber


local NewRLHandler = BasePlugin:extend()


local RATELIMIT_LIMIT = "X-RateLimit-Limit"
local RATELIMIT_REMAINING = "X-RateLimit-Remaining"


NewRLHandler.PRIORITY = 902
NewRLHandler.VERSION = "1.3.4"


local human_window_size_lookup = {
  [1]        = "second",
  [60]       = "minute",
  [3600]     = "hour",
  [86400]    = "day",
  [2592000]  = "month",
  [31536000] = "year",
}


local id_lookup = {
  ip = function(conf)
    return kong.client.get_forwarded_ip()
  end,
  credential = function(conf)
    return kong.client.get_credential() and
           kong.client.get_credential().id
  end,
  consumer = function(conf)
    -- try the consumer, fall back to credential
    return kong.client.get_consumer() and
           kong.client.get_consumer().id or
           kong.client.get_credential() and
           kong.client.get_credential().id
  end,
  service = function(conf)
    return kong.service.id
  end,
  header = function(conf)
    return kong.request.get_header(conf.header_name)
  end,
}


local function new_namespace(config, init_timer)
  kong.log.debug("attempting to add namespace ", config.namespace)

  local ok, err = pcall(function()
    local strategy = config.strategy == "cluster" and
                     kong.configuration.database or
                     "redis"

    local strategy_opts = strategy == "redis" and config.redis

    -- no shm was specified, try the default value specified in the schema
    local dict_name = config.dictionary_name
    if dict_name == nil then
      dict_name = schema.fields.dictionary_name.default
      kong.log.warn("[rate-limiting-advanced] no shared dictionary was specified.",
        " Trying the default value '", dict_name, "'...")
    end

    -- if dictionary name was passed but doesn't exist, fallback to kong
    if ngx.shared[dict_name] == nil then
      kong.log.notice("[rate-limiting-advanced] specified shared dictionary '", dict_name,
        "' doesn't exist. Falling back to the 'kong' shared dictionary")
      dict_name = "kong"
    end

    kong.log.notice("[rate-limiting-advanced] using shared dictionary '"
                         .. dict_name .. "'")

    ratelimiting.new({
      namespace     = config.namespace,
      sync_rate     = config.sync_rate,
      strategy      = strategy,
      strategy_opts = strategy_opts,
      dict          = dict_name,
      window_sizes  = config.window_size,
      db            = kong.db,
    })
  end)

  local ret = true

  -- if we created a new namespace, start the recurring sync timer and
  -- run an intial sync to fetch our counter values from the data store
  -- (if applicable)
  if ok then
    if init_timer and config.sync_rate > 0 then
      local rate = config.sync_rate
      local when = rate - (ngx.now() - (math.floor(ngx.now() / rate) * rate))
      kong.log.debug("initial sync in ", when, " seconds")
      ngx.timer.at(when, ratelimiting.sync, config.namespace)

      -- run the fetch from a timer because it uses cosockets
      -- kong patches this for psql and c*, but not redis
      ngx.timer.at(0, ratelimiting.fetch, config.namespace, ngx.now())
    end

  else
    kong.log.err("err in creating new ratelimit namespace: ",
                     err)
    ret = false
  end

  return ret
end

local function each_by_name(entity, name)
  local iter = entity:each(1000)
  local function iterator()
    local element, err = iter()
    if err then return nil, err end
    if element == nil then return end
    if element.name == name then return element, nil end
    return iterator()
  end

  return iterator
end

function NewRLHandler:new()
  NewRLHandler.super.new(self, "new-rl")
  event_hooks.publish("rate-limiting-advanced", "rate-limit-exceeded", {
    fields = { "consumer", "ip", "service", "rate", "limit", "window" },
    unique = { "consumer", "ip", "service" },
    description = "Run an event when a rate limit has been exceeded",
  })
end

local function create_namespaces()
  -- to start with, load existing plugins and create the
  -- namespaces/sync timers
  local namespaces = {}
  for plugin, err in each_by_name(kong.db.plugins, "rate-limiting-advanced") do
    if err then
      return nil, err
    end

    local namespace = plugin.config.namespace

    if not namespaces[namespace] then
      local ret = new_namespace(plugin.config, true)

      if ret then
        namespaces[namespace] = true
      end
    end
  end
  return true
end


function NewRLHandler:init_worker()
  local worker_events = kong.worker_events

  local _, err = create_namespaces()
  if err then
    kong.log.err("err in fetching plugins: ", err)
  end

  -- event handlers to update recurring sync timers

  -- catch any plugins update and forward config data to each worker
  worker_events.register(function(data)
    if data.entity.name == "rate-limiting-advanced" then
      worker_events.post("rl", data.operation, data.entity.config)
    end
  end, "crud", "plugins")

  -- new plugin? try to make a namespace!
  worker_events.register(function(config)
    if not ratelimiting.config[config.namespace] then
      new_namespace(config, true)
    end
  end, "rl", "create")

  -- updates should clear the existing config and create a new
  -- namespace config. we do not initiate a new fetch/sync recurring
  -- timer as it's already running in the background
  worker_events.register(function(config)
    kong.log.debug("clear and reset ", config.namespace)

    -- if the previous config did not have a background timer,
    -- we need to start one
    local start_timer = false
    if ratelimiting.config[config.namespace].sync_rate <= 0 and
       config.sync_rate > 0 then

      start_timer = true
    end

    ratelimiting.clear_config(config.namespace)
    new_namespace(config, start_timer)

    -- clear the timer if we dont need it
    if config.sync_rate <= 0 then
      if ratelimiting.config[config.namespace] then
        ratelimiting.config[config.namespace].kill = true

      else
        kong.log.warn("did not find namespace ", config.namespace, " to kill")
      end
    end
  end, "rl", "update")

  -- nuke this from orbit
  worker_events.register(function(config)
    -- set the kill flag on this namespace
    -- this will clear the config at the next sync() execution, and
    -- abort the recurring syncs
    if ratelimiting.config[config.namespace] then
      ratelimiting.config[config.namespace].kill = true

    else
      kong.log.warn("did not find namespace ", config.namespace, " to kill")
    end
  end, "rl", "delete")
end

function NewRLHandler:access(conf)
  local key = id_lookup[conf.identifier](conf)

  -- legacy logic, if authenticated consumer or credential is not found
  -- use the IP
  if not key then
    key = id_lookup["ip"]()
  end

  local deny

  -- if this worker has not yet seen the "rl:create" event propagated by the
  -- instatiation of a new plugin, create the namespace. in this case, the call
  -- to new_namespace in the registered rl handler will never be called on this
  -- worker
  --
  -- this workaround will not be necessary when real IPC is implemented for
  -- inter-worker communications
  --
  -- changes in https://github.com/Kong/kong-plugin-enterprise-rate-limiting/pull/35
  -- currently rely on this in scenarios where workers initialize without database availability
  if not ratelimiting.config[conf.namespace] then
    new_namespace(conf, true)
  end

  for i = 1, #conf.window_size do
    local window_size = tonumber(conf.window_size[i])
    local limit       = tonumber(conf.limit[i])

    -- if we have exceeded any rate, we should not increment any other windows,
    -- butwe should still show the rate to the client, maintaining a uniform
    -- set of response headers regardless of whether we block the request
    local rate
    if deny then
      rate = ratelimiting.sliding_window(key, window_size, nil, conf.namespace)

    else
      rate = ratelimiting.increment(key, window_size, 1, conf.namespace,
                                    conf.window_type == "fixed" and 0 or nil)
    end

    -- legacy logic of naming rate limiting headers. if we configured a window
    -- size that looks like a human friendly name, give that name
    local window_name = human_window_size_lookup[window_size] or window_size

    if not conf.hide_client_headers then
      ngx.header[RATELIMIT_LIMIT .. "-" .. window_name] = limit
      ngx.header[RATELIMIT_REMAINING .. "-" .. window_name] = max(limit - rate, 0)
    end

    if rate > limit then
      deny = true
      -- only gets emitted when kong.configuration.databus_enabled = true
      -- no need to if here
      -- XXX we are doing it on this flow of code because it's easier to
      -- get the rate and the limit that triggered it. Move it somewhere
      -- general later.
      event_hooks.emit("rate-limiting-advanced", "rate-limit-exceeded", {
        consumer = kong.client.get_consumer() or {},
        ip = kong.client.get_forwarded_ip(),
        service = kong.router.get_service() or {},
        rate = rate,
        limit = limit,
        window = window_name,
      })
    end
  end

  if deny then
    return kong.response.exit(429, { message = "API rate limit exceeded" })
  end
end

return NewRLHandler
