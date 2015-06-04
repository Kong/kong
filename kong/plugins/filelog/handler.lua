-- Copyright (C) Mashape, Inc.

local BasePlugin = require "kong.plugins.base_plugin"
local log = require "kong.plugins.filelog.log"

local FileLogHandler = BasePlugin:extend()

function FileLogHandler:new()
  FileLogHandler.super.new(self, "filelog")
end

function FileLogHandler:log(conf)
  FileLogHandler.super.log(self)
  log.execute(conf)
end

return FileLogHandler
