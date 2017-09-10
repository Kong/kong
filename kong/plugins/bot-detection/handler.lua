local BasePlugin = require "kong.plugins.base_plugin"
local responses = require "kong.tools.responses"
local rules = require "kong.plugins.bot-detection.rules"
local strip = require("kong.tools.utils").strip
local lrucache = require "resty.lrucache"

local ipairs = ipairs
local get_headers = ngx.req.get_headers
local re_find = ngx.re.find

local BotDetectionHandler = BasePlugin:extend()

BotDetectionHandler.PRIORITY = 2500

local MATCH_EMPTY     = 0
local MATCH_WHITELIST = 1
local MATCH_BLACKLIST = 2
local MATCH_BOT       = 3

-- per-worker cache of matched UAs
-- we could use the kong cache mechanism, but purging a subset of
-- the cache is a pain, and the lookup here isn't so expensive that
-- we really worry about it. so we just cache per worker and invalidate
-- when the plugin has been updated
local ua_cache = {}
local UA_CACHE_SIZE = 10 ^ 4

local function get_user_agent()
  local user_agent = get_headers()["user-agent"]
  if type(user_agent) == "table" then
    return nil, "Only one User-Agent header allowed"
  end
  return user_agent
end

local function examine_agent(user_agent, conf)
  user_agent = strip(user_agent)

  if conf.whitelist then
    for _, rule in ipairs(conf.whitelist) do
      if re_find(user_agent, rule, "jo") then
        return MATCH_WHITELIST
      end
    end
  end

  if conf.blacklist then
    for _, rule in ipairs(conf.blacklist) do
      if re_find(user_agent, rule, "jo") then
        return MATCH_BLACKLIST
      end
    end
  end

  for _, rule in ipairs(rules.bots) do
    if re_find(user_agent, rule, "jo") then
      return MATCH_BOT
    end
  end

  return MATCH_EMPTY
end

function BotDetectionHandler:new()
  BotDetectionHandler.super.new(self, "bot-detection")
end

function BotDetectionHandler:init_worker()
  local singletons    = require "kong.singletons"
  local worker_events = singletons.worker_events
  local dao_factory   = singletons.dao

  -- load our existing plugins to create our cache spaces
  local plugins, err = dao_factory.plugins:find_all({
    name = "bot-detection",
  })
  if err then
    ngx.log(ngx.ERR, "err in fetching plugins: ", err)
  end

  for i = 1, #plugins do
    ua_cache[plugins[i].api_id] = lrucache.new(UA_CACHE_SIZE)
  end

  -- catch updates and tell each worker to adjust their cache
  -- accordingly. for create/updates we create/purge the cache
  -- by simply creating a new lua table; for deletions, as we no
  -- longer need this cache data, we just remove it
  worker_events.register(function(data)
    if data.entity.name == "bot-detection" then
      worker_events.post("bot-detection-invalidate", data.operation,
                         data.entity)
    end
  end, "crud", "plugins")

  worker_events.register(function(entity)
    ua_cache[entity.api_id] = lrucache.new(UA_CACHE_SIZE)
  end, "bot-detection-invalidate", "create")

  worker_events.register(function(entity)
    ua_cache[entity.api_id] = lrucache.new(UA_CACHE_SIZE)
  end, "bot-detection-invalidate", "update")

  worker_events.register(function(entity)
    ua_cache[entity.api_id] = nil
  end, "bot-detection-invalidate", "delete")
end

function BotDetectionHandler:access(conf)
  BotDetectionHandler.super.access(self)

  local user_agent, err = get_user_agent()
  if err then
    return responses.send_HTTP_BAD_REQUEST(err)
  end

  if not user_agent then
    return
  end

  local api_id = ngx.ctx.api.id
  local match  = ua_cache[api_id]:get(user_agent)

  if not match then
    match = examine_agent(user_agent, conf)
    ua_cache[api_id]:set(user_agent, match)
  end

  -- if we saw a blacklisted UA or bot, return forbidden. otherwise,
  -- fall out of our handler
  if match > 1 then
    return responses.send_HTTP_FORBIDDEN()
  end
end

return BotDetectionHandler
