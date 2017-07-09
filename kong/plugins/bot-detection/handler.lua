local BasePlugin = require "kong.plugins.base_plugin"
local responses = require "kong.tools.responses"
local rules = require "kong.plugins.bot-detection.rules"
local strip = require("kong.tools.utils").strip
local lrucache = require "resty.lrucache"

local ipairs = ipairs
local get_headers = ngx.req.get_headers
local re_match = ngx.re.match

local BotDetectionHandler = BasePlugin:extend()

BotDetectionHandler.PRIORITY = 2500

local MATCH_EMPTY     = 0
local MATCH_WHITELIST = 1
local MATCH_BLACKLIST = 2
local MATCH_BOT       = 3

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
      if re_match(user_agent, rule) then
        return MATCH_WHITELIST
      end
    end
  end

  if conf.blacklist then
    for _, rule in ipairs(conf.blacklist) do
      if re_match(user_agent, rule) then
        return MATCH_BLACKLIST
      end
    end
  end

  for _, rule in ipairs(rules.bots) do
    if re_match(user_agent, rule) then
      return MATCH_BOT
    end
  end

  return MATCH_EMPTY
end

function BotDetectionHandler:new()
  BotDetectionHandler.super.new(self, "bot-detection")
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

  local ua_cache = conf.ua_cache
  if not ua_cache then
    ua_cache = lrucache.new(UA_CACHE_SIZE)
    conf.ua_cache = ua_cache
  end
  local match  = ua_cache:get(user_agent)

  if not match then
    match = examine_agent(user_agent, conf)
    ua_cache:set(user_agent, match)
  end

  -- if we saw a blacklisted UA or bot, return forbidden. otherwise,
  -- fall out of our handler
  if match > 1 then
    return responses.send_HTTP_FORBIDDEN()
  end
end

return BotDetectionHandler
