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

local ffi = require "ffi"
local base = require "resty.core.base"


local C = ffi.C
local ngx = ngx
local tonumber = tonumber
local registry = debug.getregistry()


local FFI_NO_REQ_CTX = base.FFI_NO_REQ_CTX


local _M = {}


function _M.stash_ref()
  local r = base.get_request()
  if not r then
    ngx.log(ngx.WARN, "could not stash ngx.ctx ref: no request found")
    return
  end

  do
    local ctx_ref = ngx.var.ctx_ref
    if not ctx_ref or ctx_ref ~= "" then
      return
    end

    local _ = ngx.ctx -- load context if not previously loaded
  end

  local ctx_ref = C.ngx_http_lua_ffi_get_ctx_ref(r)
  if ctx_ref == FFI_NO_REQ_CTX then
    ngx.log(ngx.WARN, "could not stash ngx.ctx ref: no ctx found")
    return
  end

  ngx.var.ctx_ref = ctx_ref
end


function _M.apply_ref()
  local r = base.get_request()
  if not r then
    ngx.log(ngx.WARN, "could not apply ngx.ctx: no request found")
    return
  end

  local ctx_ref = ngx.var.ctx_ref
  if not ctx_ref or ctx_ref == "" then
    return
  end

  ctx_ref = tonumber(ctx_ref)
  if not ctx_ref then
    return
  end

  local orig_ctx = registry.ngx_lua_ctx_tables[ctx_ref]
  if not orig_ctx then
    ngx.log(ngx.WARN, "could not apply ngx.ctx: no ctx found")
    return
  end

  ngx.ctx = orig_ctx
  ngx.var.ctx_ref = ""
end


return _M
