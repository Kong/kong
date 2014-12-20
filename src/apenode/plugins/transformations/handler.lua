-- Copyright (C) Mashape, Inc.

local BasePlugin = require "apenode.base_plugin"
local header_filter = require "apenode.plugins.transformations.header_filter"
local body_filter = require "apenode.plugins.transformations.body_filter"

local TransformationsHandler = BasePlugin:extend()

function TransformationsHandler:new()
  TransformationsHandler.super:new("transformations")
end

function TransformationsHandler:header_filter(conf)
  TransformationsHandler.super:header_filter()
  header_filter.execute(conf)
end

function TransformationsHandler:body_filter(conf)
  TransformationsHandler.super:body_filter()
  body_filter.execute(conf)
end

return TransformationsHandler
