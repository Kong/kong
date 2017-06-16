local BasePlugin = require "kong.plugins.base_plugin"
local responses = require "kong.tools.responses"
local rules = require "kong.plugins.bot-detection.rules"
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

    if conf.whitelist then
      for _, rule in ipairs(conf.whitelist) do
        if re_match(user_agent, rule) then
          return
        end
      end
    end

    if conf.blacklist then
      for _, rule in ipairs(conf.blacklist) do
        if re_match(user_agent, rule) then
          return responses.send_HTTP_FORBIDDEN()
        end
      end
    end
  
    for _, rule in ipairs(rules.bots) do
      if re_match(user_agent, rule) then
        return responses.send_HTTP_FORBIDDEN()
      end
    end
  end
end

return BotDetectionHandler
