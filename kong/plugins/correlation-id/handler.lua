-- Copyright (C) Mashape, Inc.

local BasePlugin = require "kong.plugins.base_plugin"
local uuid = require "lua_uuid"
local req_set_header = ngx.req.set_header
local req_get_headers = ngx.req.get_headers

local CorrelationIdHandler = BasePlugin:extend()

local worker_uuid
local worker_counter

local generators = setmetatable({
	["uuid"] = function()
    return uuid()
	end,
	["uuid#counter"] = function()
    worker_counter = worker_counter + 1
    return worker_uuid.."#"..worker_counter
	end,
}, { __index = function(self, generator)
    ngx.log(ngx.ERR, "Invalid generator: "..generator)
end
})

function CorrelationIdHandler:new()
  CorrelationIdHandler.super.new(self, "correlation-id")
end

function CorrelationIdHandler:init_worker()
  CorrelationIdHandler.super.init_worker(self)
  worker_uuid = uuid()
  worker_counter = 0
end

function CorrelationIdHandler:access(conf)
  CorrelationIdHandler.super.access(self)

  -- Set header for upstream
  local header_value = req_get_headers()[conf.header_name]
  if not header_value then
    -- Generate the header value
    header_value = generators[conf.generator]()
    req_set_header(conf.header_name, header_value)
  end

  if conf.echo_downstream then
    -- For later use, to echo it back downstream
    ngx.ctx.correlationid_header_value = header_value
  end
end

function CorrelationIdHandler:header_filter(conf)
  CorrelationIdHandler.super.header_filter(self)
  if conf.echo_downstream then
    ngx.header[conf.header_name] = ngx.ctx.correlationid_header_value
  end
end

return CorrelationIdHandler
