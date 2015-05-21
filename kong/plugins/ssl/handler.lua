-- Copyright (C) Mashape, Inc.

local BasePlugin = require "kong.plugins.base_plugin"
local certificate = require "kong.plugins.ssl.certificate"
local access = require "kong.plugins.ssl.access"

local SSLHandler = BasePlugin:extend()

function SSLHandler:new()
  SSLHandler.super.new(self, "ssl")
end

function SSLHandler:certificate(conf)
  SSLHandler.super.certificate(self)
  certificate.execute(conf)
end

function SSLHandler:access(conf)
  SSLHandler.super.access(self)
  access.execute(conf)
end

SSLHandler.PRIORITY = 3000

return SSLHandler
