-- Copyright (C) Kong Inc.

local BasePlugin   = require "kong.plugins.base_plugin"
local ratelimiting = require "kong.tools.public.rate-limiting"
local responses    = require "kong.tools.responses"
local singletons   = require "kong.singletons"

local max      = math.max
local tonumber = tonumber


local NewRLHandler = BasePlugin:extend()


local RATELIMIT_LIMIT = "X-RateLimit-Limit"
local RATELIMIT_REMAINING = "X-RateLimit-Remaining"


NewRLHandler.PRIORITY = 901


local human_window_size_lookup = {
  [1]        = "second",
  [60]       = "minute",
  [3600]     = "hour",
  [86400]    = "day",
  [2592000]  = "month",
  [31536000] = "year",
}


local id_lookup = {
  ip = function()
    return ngx.var.remote_addr
  end,
  credential = function()
    return ngx.ctx.authenticated_credential and
           ngx.ctx.authenticated_credential.id
  end,
  consumer = function()
    -- try the consumer, fall back to credential
    return ngx.ctx.authenticated_consumer and
           ngx.ctx.authenticated_consumer.id or
           ngx.ctx.authenticated_credential and
           ngx.ctx.authenticated_credential.id
  end
}


local function new_namespace(config, init_timer)
  ngx.log(ngx.DEBUG, "attempting to add namespace ", config.namespace)

  local ok, err = pcall(function()
    local strategy = config.strategy == "cluster" and
                     singletons.configuration.database or
                     "redis"

    local strategy_opts = strategy == "redis" and config.redis

    ratelimiting.new({
      namespace     = config.namespace,
      sync_rate     = config.sync_rate,
      strategy      = strategy,
      strategy_opts = strategy_opts,
      dict          = "kong",
      window_sizes  = config.window_size,
      dao_factory   = singletons.dao,
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
      ngx.log(ngx.DEBUG, "initial sync in ", when, " seconds")
      ngx.timer.at(when, ratelimiting.sync, config.namespace)

      -- run the fetch from a timer because it uses cosockets
      -- kong patches this for psql and c*, but not redis
      ngx.timer.at(0, ratelimiting.fetch, config.namespace, ngx.now())
    end

  else
    ngx.log(ngx.ERR, "err in creating new ratelimit namespace: ",
                     err)
    ret = false
  end

  return ret
end


function NewRLHandler:new()
  NewRLHandler.super.new(self, "new-rl")
end

function NewRLHandler:init_worker()
  local worker_events = singletons.worker_events
  local dao_factory   = singletons.dao

  -- to start with, load existing plugins and create the
  -- namespaces/sync timers
  local plugins, err = dao_factory.plugins:find_all({
    name = "rate-limiting",
  })
  if err then
    ngx.log(ngx.ERR, "err in fetching plugins: ", err)
  end

  local namespaces = {}
  for i = 1, #plugins do
    local namespace = plugins[i].config.namespace

    if not namespaces[namespace] then
      local ret = new_namespace(plugins[i].config, true)

      if ret then
        namespaces[namespace] = true
      end
    end
  end

  -- event handlers to update recurring sync timers

  -- catch any plugins update and forward config data to each worker
  worker_events.register(function(data)
    if data.entity.name == "rate-limiting" then
      worker_events.post("rl", data.operation, data.entity.config)
    end
  end, "crud", "plugins")

  -- new plugin? try to make a namespace!
  worker_events.register(function(config)
    new_namespace(config, true)
  end, "rl", "create")

  -- updates should clear the existing config and create a new
  -- namespace config. we do not initiate a new fetch/sync recurring
  -- timer as it's already running in the background
  worker_events.register(function(config)
    ngx.log(ngx.DEBUG, "clear and reset ", config.namespace)

    ratelimiting.clear_config(config.namespace)
    new_namespace(config)
  end, "rl", "update")

  -- nuke this from orbit
  worker_events.register(function(config)
    -- set the kill flag on this namespace
    -- this will clear the config at the next sync() execution, and
    -- abort the recurring syncs
    if ratelimiting.config[config.namespace] then
      ratelimiting.config[config.namespace].kill = true

    else
      ngx.log(ngx.WARN, "did not find namespace ", config.namespace, " to kill")
    end
  end, "rl", "delete")
end

function NewRLHandler:access(conf)
  local key = id_lookup[conf.identifier]()

  -- legacy logic, if authenticated consumer or credential is not found
  -- use the IP
  if not key then
    key = id_lookup["ip"]()
  end

  local deny

  for i = 1, #conf.window_size do
    local window_size = tonumber(conf.window_size[i])
    local limit       = tonumber(conf.limit[i])

    local rate = ratelimiting.increment(key, window_size, 1, conf.namespace)

    -- legacy logic of naming rate limiting headers. if we configured a window
    -- size that looks like a human friendly name, give that name
    local window_name = human_window_size_lookup[window_size] or window_size

    ngx.header[RATELIMIT_LIMIT .. "-" .. window_name] = limit
    ngx.header[RATELIMIT_REMAINING .. "-" .. window_name] = max(limit - rate, 0)

    if rate > limit then
      deny = true
    end
  end

  if deny then
    return responses.send(429, "API rate limit exceeded")
  end
end

return NewRLHandler
