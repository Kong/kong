local BasePlugin = require "kong.plugins.base_plugin"
local responses = require "kong.tools.responses"
local response, _ = require "kong.yop.response"()

local IPWhiteListHandler = BasePlugin:extend()

function IPWhiteListHandler:new() IPWhiteListHandler.super.new(self, "ip-whitelist") end

function IPWhiteListHandler:access(conf)
  IPWhiteListHandler.super.access(self)

  if conf==nil then return end

end

IPWhiteListHandler.PRIORITY = 801
return IPWhiteListHandler
