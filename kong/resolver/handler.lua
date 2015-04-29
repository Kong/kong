-- Kong resolver core-plugin
--
-- This core-plugin is executed before any other, and allows to map a Host header
-- to an API added to Kong. If the API was found, it will set the $backend_url variable
-- allowing nginx to proxy the request as defined in the nginx configuration.
--
-- Executions: 'access', 'header_filter'

local access = require "kong.resolver.access"
local header_filter = require "kong.resolver.header_filter"
local BasePlugin = require "kong.plugins.base_plugin"

local ResolverHandler = BasePlugin:extend()

function ResolverHandler:new()
  ResolverHandler.super.new(self, "resolver")
end

function ResolverHandler:access(conf)
  ResolverHandler.super.access(self)
  access.execute(conf)
end

function ResolverHandler:header_filter(conf)
  ResolverHandler.super.header_filter(self)
  header_filter.execute(conf)
end

return ResolverHandler
