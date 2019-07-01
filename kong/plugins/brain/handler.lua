-- brain plugin handler.
-- Buffers request/response bodies if asked so in the plugin's config.
-- Caches the server's address to avoid further syscalls.
--
-- Maintains one ALF Buffer per Brain plugin per worker.

local BasePlugin = require "kong.plugins.base_plugin"
local Buffer = require "kong.plugins.brain.buffer"

local read_body = ngx.req.read_body
local get_body_data = ngx.req.get_body_data

local _alf_buffers = {} -- buffers per-route / -api
local _server_addr
local allowed_to_run

local BrainHandler = BasePlugin:extend()

BrainHandler.PRIORITY = 3
BrainHandler.VERSION = "1.0.0"

function BrainHandler:new()
  BrainHandler.super.new(self, "brain")
  if string.match(kong.version, "enterprise") then
    allowed_to_run = true
  else
    allowed_to_run = false
  end
end

function BrainHandler:access(conf)
  BrainHandler.super.access(self)

  if allowed_to_run then
    if not _server_addr then
      _server_addr = ngx.var.server_addr
    end

    if conf.log_bodies then
      read_body()
      ngx.ctx.brain = {req_body = get_body_data()}
    end
  else
    kong.log.err("This plugin is intended to work with only Kong Enterprise.")
  end
end

function BrainHandler:body_filter(conf)
  BrainHandler.super.body_filter(self)

  -- XXX EE: if request was cached, don' t proceed - no body to read
  if allowed_to_run then
    local ctx = ngx.ctx
    if ctx.proxy_cache_hit then
      return
    end

    if conf.log_bodies then
      local chunk = ngx.arg[1]
      local res_body = ctx.brain and ctx.brain.res_body or ""
      res_body = res_body .. (chunk or "")

      if ctx.brain then
        ctx.brain.res_body = res_body
      end
      -- catch unauth error
      if not ctx.brain then
        return { status = 403, message = "No API key found in request" }
      end
    end
  else
    kong.log.err("This plugin is intended to work with only Kong Enterprise.")
  end
end

function BrainHandler:log(conf)
  BrainHandler.super.log(self)

  -- XXX: EE: if request was cached, fill in server_addr from proxy-cache
  -- context
  if allowed_to_run then
    local ctx = ngx.ctx
    if ctx.proxy_cache_hit then
      _server_addr = ctx.proxy_cache_hit.server_addr
    end

    local route_id = conf.route_id or conf.api_id or conf.service_id

    local buf = _alf_buffers[route_id]
    if not buf then
      local err
      conf.server_addr = _server_addr
      buf, err = Buffer.new(conf)
      if not buf then
        ngx.log(ngx.ERR, "could not create ALF buffer: ", err)
        return
      end
      _alf_buffers[route_id] = buf
    end

    local req_body, res_body

    local ctx = ngx.ctx

    -- XXX EE: if request was cached, fill in the bodies from the proxy-cache
    -- context
    if ctx.proxy_cache_hit then
      req_body = ctx.proxy_cache_hit.req.body
      res_body = ctx.proxy_cache_hit.res.body
    elseif ctx.brain then
      req_body = ctx.brain.req_body
      res_body = ctx.brain.res_body
    end

    buf:add_entry(ngx, req_body, res_body)
  else
    kong.log.err("This plugin is intended to work with only Kong Enterprise.")
  end
end

return BrainHandler
