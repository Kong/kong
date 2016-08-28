local BasePlugin = require "kong.plugins.base_plugin"
local responses = require "kong.tools.responses"
local rules = require "kong.plugins.bot-detection.rules"
local bot_cache = require "kong.plugins.bot-detection.cache"
local strip = require("kong.tools.utils").strip

local ipairs = ipairs
local get_headers = ngx.req.get_headers
local re_match = ngx.re.match

local BotDetectionHandler = BasePlugin:extend()

BotDetectionHandler.PRIORITY = 2500

local function get_user_agent()
  local user_agent = get_headers()["user-agent"]
  if type(user_agent) == "table" then
    return nil, "Only one User-Agent header allowed"
  end
  return user_agent
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

  if user_agent then
    user_agent = strip(user_agent)

    -- Cache key, per API
    local cache_key = ngx.ctx.api.id..":"..user_agent

    -- The cache already has the user_agents that should be blocked
    -- So we avoid matching the regexes everytime
    local cached_match = bot_cache.get(cache_key)
    if cached_match then 
      return
    elseif cached_match == false then
      return responses.send_HTTP_FORBIDDEN()
    end

    if conf.whitelist then
      for _, rule in ipairs(conf.whitelist) do
        if re_match(user_agent, rule) then
          bot_cache.set(cache_key, true)
          return
        end
      end
    end

    if conf.blacklist then
      for _, rule in ipairs(conf.blacklist) do
        if re_match(user_agent, rule) then
          bot_cache.set(cache_key, false)
          return responses.send_HTTP_FORBIDDEN()
        end
      end
    end
  
    for _, rule in ipairs(rules.bots) do
      if re_match(user_agent, rule) then
        bot_cache.set(cache_key, false)
        return responses.send_HTTP_FORBIDDEN()
      end
    end

    bot_cache.set(cache_key, true)
  end
end

return BotDetectionHandler