-- A module for sharing ngx.ctx between subrequests.
-- Original work by Alex Zhang (openresty/lua-nginx-module/issues/1057)
-- updated by 3scale/apicast.
--
-- Copyright (c) 2016 3scale Inc.
-- Licensed under the Apache License, Version 2.0.
-- License text: See LICENSE
--
-- Modifications by Kong Inc.
--   * updated module functions signatures
--   * made module function idempotent
--   * replaced thrown errors with warn logs
--   * allow passing of context
--   * updated to work with new 1.19.x apis

local ffi = require "ffi"
local base = require "resty.core.base"
require "resty.core.ctx"


local C = ffi.C
local ngx = ngx
local var = ngx.var
local ngx_log = ngx.log
local ngx_WARN = ngx.WARN
local tonumber = tonumber
local registry = debug.getregistry()
local subsystem = ngx.config.subsystem
local get_request = base.get_request


local ngx_lua_ffi_get_ctx_ref
if subsystem == "http" then
  ngx_lua_ffi_get_ctx_ref = C.ngx_http_lua_ffi_get_ctx_ref
elseif subsystem == "stream" then
  ngx_lua_ffi_get_ctx_ref = C.ngx_stream_lua_ffi_get_ctx_ref
end


local in_ssl_phase = ffi.new("int[1]")
local ssl_ctx_ref = ffi.new("int[1]")


local FFI_NO_REQ_CTX = base.FFI_NO_REQ_CTX


local _M = {}


function _M.stash_ref(ctx)
  local r = get_request()
  if not r then
    ngx_log(ngx_WARN, "could not stash ngx.ctx ref: no request found")
    return
  end

  do
    local ctx_ref = var.ctx_ref
    if not ctx_ref or ctx_ref ~= "" then
      return
    end

    if not ctx then
      local _ = ngx.ctx -- load context if not previously loaded
    end
  end
  local ctx_ref = ngx_lua_ffi_get_ctx_ref(r, in_ssl_phase, ssl_ctx_ref)
  if ctx_ref == FFI_NO_REQ_CTX then
    ngx_log(ngx_WARN, "could not stash ngx.ctx ref: no ctx found")
    return
  end

  var.ctx_ref = ctx_ref
end


function _M.apply_ref()
  if not get_request() then
    ngx_log(ngx_WARN, "could not apply ngx.ctx: no request found")
    return
  end

  local ctx_ref = var.ctx_ref
  if not ctx_ref or ctx_ref == "" then
    return
  end

  ctx_ref = tonumber(ctx_ref)
  if not ctx_ref then
    return
  end

  local orig_ctx = registry.ngx_lua_ctx_tables[ctx_ref]
  if not orig_ctx then
    ngx_log(ngx_WARN, "could not apply ngx.ctx: no ctx found")
    return
  end

  ngx.ctx = orig_ctx
  var.ctx_ref = ""
end


return _M
