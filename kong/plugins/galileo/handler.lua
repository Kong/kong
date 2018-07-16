-- Galileo plugin handler.
-- Buffers request/response bodies if asked so in the plugin's config.
-- Caches the server's address to avoid further syscalls.
--
-- Maintains one ALF Buffer per galileo plugin per worker.

local BasePlugin = require "kong.plugins.base_plugin"
local Buffer = require "kong.plugins.log-buffering.buffer"
local Producer = require "kong.plugins.galileo.producer"
local Sender = require "kong.plugins.galileo.sender"

local ngx_log = ngx.log
local read_body = ngx.req.read_body
local get_body_data = ngx.req.get_body_data

local _alf_buffers = {} -- buffers per-route / -api
local _server_addr

local GalileoHandler = BasePlugin:extend()

GalileoHandler.PRIORITY = 3
GalileoHandler.VERSION = "0.1.0"


local function log(lvl, ...)
  ngx_log(lvl, "[galileo] ", ...)
end


function GalileoHandler:new()
  GalileoHandler.super.new(self, "galileo")
end

function GalileoHandler:access(conf)
  GalileoHandler.super.access(self)

  if not _server_addr then
    _server_addr = ngx.var.server_addr
  end

  if conf.log_bodies then
    read_body()
    ngx.ctx.galileo = {req_body = get_body_data()}
  end
end

function GalileoHandler:body_filter(conf)
  GalileoHandler.super.body_filter(self)

  if conf.log_bodies then
    local chunk = ngx.arg[1]
    local ctx = ngx.ctx
    local res_body = ctx.galileo and ctx.galileo.res_body or ""
    res_body = res_body .. (chunk or "")
    ctx.galileo.res_body = res_body
  end
end

function GalileoHandler:log(conf)
  GalileoHandler.super.log(self)

  local route_id = conf.route_id or conf.api_id

  local buf = _alf_buffers[route_id]
  if not buf then
    local err
    conf.server_addr = _server_addr
    buf, err = Buffer.new("galileo", conf, Producer.new(conf), Sender.new(conf), log)
    if not buf then
      log(ngx.ERR, "could not create ALF buffer: ", err)
      return
    end
    _alf_buffers[route_id] = buf
  end

  local req_body, res_body

  local ctx = ngx.ctx
  if ctx.galileo then
    req_body = ctx.galileo.req_body
    res_body = ctx.galileo.res_body
  end

  buf:add_entry(ngx, req_body, res_body)
end

return GalileoHandler
