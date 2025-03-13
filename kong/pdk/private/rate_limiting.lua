local table_new    = require("table.new")

local type         = type
local pairs        = pairs
local assert       = assert
local tostring     = tostring
local resp_header  = ngx.header

-- determine the number of pre-allocated fields at runtime
local max_fields_n = 4

local _M = {}


local function _validate_key(key, arg_n, func_name)
  local typ = type(key)
  if typ ~= "string" then
    local msg = string.format(
      "arg #%d `key` for function `%s` must be a string, got %s",
      arg_n,
      func_name,
      typ
    )
    error(msg, 3)
  end
end


local function _validate_value(value, arg_n, func_name)
  local typ = type(value)
  if typ ~= "number" and typ ~= "string" then
    local msg = string.format(
      "arg #%d `value` for function `%s` must be a string or a number, got %s",
      arg_n,
      func_name,
      typ
    )
    error(msg, 3)
  end
end


local function _has_rl_ctx(ngx_ctx)
  return ngx_ctx.__rate_limiting_context__ ~= nil
end


local function _create_rl_ctx(ngx_ctx)
  assert(not _has_rl_ctx(ngx_ctx), "rate limiting context already exists")
  local ctx = table_new(0, max_fields_n)
  ngx_ctx.__rate_limiting_context__ = ctx
  return ctx
end


local function _get_rl_ctx(ngx_ctx)
  assert(_has_rl_ctx(ngx_ctx), "rate limiting context does not exist")
  return ngx_ctx.__rate_limiting_context__
end


local function _get_or_create_rl_ctx(ngx_ctx)
  if not _has_rl_ctx(ngx_ctx) then
    _create_rl_ctx(ngx_ctx)
  end

  local rl_ctx = _get_rl_ctx(ngx_ctx)
  return rl_ctx
end


function _M.store_response_header(ngx_ctx, key, value)
  _validate_key(key, 2, "store_response_header")
  _validate_value(value, 3, "store_response_header")

  local rl_ctx = _get_or_create_rl_ctx(ngx_ctx)
  rl_ctx[key] = value
end


function _M.get_stored_response_header(ngx_ctx, key)
  _validate_key(key, 2, "get_stored_response_header")

  if not _has_rl_ctx(ngx_ctx) then
    return nil
  end

  if not _has_rl_ctx(ngx_ctx) then
    return nil
  end

  local rl_ctx = _get_rl_ctx(ngx_ctx)
  return rl_ctx[key]
end


function _M.apply_response_headers(ngx_ctx)
  if not _has_rl_ctx(ngx_ctx) then
    return
  end

  local rl_ctx = _get_rl_ctx(ngx_ctx)
  local actual_fields_n = 0

  for k, v in pairs(rl_ctx) do
    resp_header[k] = tostring(v)
    actual_fields_n = actual_fields_n + 1
  end

  if actual_fields_n > max_fields_n then
    local msg = string.format(
      "[private-rl-pdk] bumpping pre-allocated fields from %d to %d for performance reasons",
      max_fields_n,
      actual_fields_n
    )
    ngx.log(ngx.INFO, msg)
    max_fields_n = actual_fields_n
  end
end

return _M
