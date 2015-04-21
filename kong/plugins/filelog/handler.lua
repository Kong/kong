-- Copyright (C) Mashape, Inc.

local basic_serializer = require "kong.plugins.log_serializers.basic"
local BasePlugin = require "kong.plugins.base_plugin"
local cjson = require "cjson"

local FileLogHandler = BasePlugin:extend()

function FileLogHandler:new()
  FileLogHandler.super.new(self, "filelog")
end

function FileLogHandler:log(conf)
  FileLogHandler.super.log(self)

  local message = basic_serializer.serialize(ngx)
  ngx.log(ngx.INFO, cjson.encode(message))
end

return FileLogHandler
