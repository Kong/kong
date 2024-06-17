-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local table_new    = require("table.new")
local buffer       = require("string.buffer")

local type         = type
local pairs        = pairs
local assert       = assert
local tostring     = tostring
local resp_header  = ngx.header

local tablex_keys  = require("pl.tablex").keys

local RL_LIMIT     = "RateLimit-Limit"
local RL_REMAINING = "RateLimit-Remaining"
local RL_RESET     = "RateLimit-Reset"
local RETRY_AFTER  = "Retry-After"


-- determine the number of pre-allocated fields at runtime
local max_fields_n = 4
local buf = buffer.new(64)

local LIMIT_BY = {
  second = {
    limit = "X-RateLimit-Limit-Second",
    remain = "X-RateLimit-Remaining-Second",
    limit_segment_0 = "X-",
    limit_segment_1 = "RateLimit-Limit-",
    limit_segment_3 = "-Second",
    remain_segment_0 = "X-",
    remain_segment_1 = "RateLimit-Remaining-",
    remain_segment_3 = "-Second",
  },
  minute = {
    limit = "X-RateLimit-Limit-Minute",
    remain = "X-RateLimit-Remaining-Minute",
    limit_segment_0 = "X-",
    limit_segment_1 = "RateLimit-Limit-",
    limit_segment_3 = "-Minute",
    remain_segment_0 = "X-",
    remain_segment_1 = "RateLimit-Remaining-",
    remain_segment_3 = "-Minute",
  },
  hour = {
    limit = "X-RateLimit-Limit-Hour",
    remain = "X-RateLimit-Remaining-Hour",
    limit_segment_0 = "X-",
    limit_segment_1 = "RateLimit-Limit-",
    limit_segment_3 = "-Hour",
    remain_segment_0 = "X-",
    remain_segment_1 = "RateLimit-Remaining-",
    remain_segment_3 = "-Hour",
  },
  day = {
    limit = "X-RateLimit-Limit-Day",
    remain = "X-RateLimit-Remaining-Day",
    limit_segment_0 = "X-",
    limit_segment_1 = "RateLimit-Limit-",
    limit_segment_3 = "-Day",
    remain_segment_0 = "X-",
    remain_segment_1 = "RateLimit-Remaining-",
    remain_segment_3 = "-Day",
  },
  month = {
    limit = "X-RateLimit-Limit-Month",
    remain = "X-RateLimit-Remaining-Month",
    limit_segment_0 = "X-",
    limit_segment_1 = "RateLimit-Limit-",
    limit_segment_3 = "-Month",
    remain_segment_0 = "X-",
    remain_segment_1 = "RateLimit-Remaining-",
    remain_segment_3 = "-Month",
  },
  year = {
    limit = "X-RateLimit-Limit-Year",
    remain = "X-RateLimit-Remaining-Year",
    limit_segment_0 = "X-",
    limit_segment_1 = "RateLimit-Limit-",
    limit_segment_3 = "-Year",
    remain_segment_0 = "X-",
    remain_segment_1 = "RateLimit-Remaining-",
    remain_segment_3 = "-Year",
  },
}

local _M = {}


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


function _M.set_basic_limit(ngx_ctx, limit, remaining, reset)
  local rl_ctx = _get_or_create_rl_ctx(ngx_ctx or ngx.ctx)

  assert(
    type(limit) == "number",
    "arg #2 `limit` for `set_basic_limit` must be a number"
  )
  assert(
    type(remaining) == "number",
    "arg #3 `remaining` for `set_basic_limit` must be a number"
  )
  assert(
    type(reset) == "number",
    "arg #4 `reset` for `set_basic_limit` must be a number"
  )

  rl_ctx[RL_LIMIT] = limit
  rl_ctx[RL_REMAINING] = remaining
  rl_ctx[RL_RESET] = reset
end

function _M.set_retry_after(ngx_ctx, reset)
  local rl_ctx = _get_or_create_rl_ctx(ngx_ctx or ngx.ctx)

  assert(
    type(reset) == "number",
    "arg #2 `reset` for `set_retry_after` must be a number"
  )

  rl_ctx[RETRY_AFTER] = reset
end

function _M.set_limit_by(ngx_ctx, limit_by, limit, remaining)
  local rl_ctx = _get_or_create_rl_ctx(ngx_ctx or ngx.ctx)

  assert(
    type(limit_by) == "string",
    "arg #2 `limit_by` for `set_limit_by` must be a string"
  )
  assert(
    type(limit) == "number",
    "arg #3 `limit` for `set_limit_by` must be a number"
  )
  assert(
    type(remaining) == "number",
    "arg #4 `remaining` for `set_limit_by` must be a number"
  )

  limit_by = LIMIT_BY[limit_by]
  assert(limit_by, "invalid limit_by")

  rl_ctx[limit_by.limit] = limit
  rl_ctx[limit_by.remain] = remaining
end

function _M.set_limit_by_with_identifier(ngx_ctx, limit_by, limit, remaining, id_seg_1, id_seg_2)
  local rl_ctx = _get_or_create_rl_ctx(ngx_ctx or ngx.ctx)

  assert(
    type(limit_by) == "string",
    "arg #2 `limit_by` for `set_limit_by_with_identifier` must be a string"
  )
  assert(
    type(limit) == "number",
    "arg #3 `limit` for `set_limit_by_with_identifier` must be a number"
  )
  assert(
    type(remaining) == "number",
    "arg #4 `remaining` for `set_limit_by_with_identifier` must be a number"
  )

  local id_seg_1_typ = type(id_seg_1)
  local id_seg_2_typ = type(id_seg_2)
  assert(
    id_seg_1_typ == "nil" or id_seg_1_typ == "string",
    "arg #5 `id_seg_1` for `set_limit_by_with_identifier` must be a string or nil"
  )
  assert(
    id_seg_2_typ == "nil" or id_seg_2_typ == "string",
    "arg #6 `id_seg_2` for `set_limit_by_with_identifier` must be a string or nil"
  )

  limit_by = LIMIT_BY[limit_by]
  if not limit_by then
    local valid_limit_bys = tablex_keys(LIMIT_BY)
    local msg = string.format(
      "arg #2 `limit_by` for `set_limit_by_with_identifier` must be one of: %s",
      table.concat(valid_limit_bys, ", ")
    )
    error(msg)
  end

  id_seg_1 = id_seg_1 or ""
  id_seg_2 = id_seg_2 or ""

  -- construct the key like X-<id_seg_1>-RateLimit-Limit-<id_seg_2>-<limit_by>
  local limit_key = buf:reset():put(
    limit_by.limit_segment_0,
    id_seg_1,
    limit_by.limit_segment_1,
    id_seg_2,
    limit_by.limit_segment_3
  ):get()

  -- construct the key like X-<id_seg_1>-RateLimit-Remaining-<id_seg_2>-<limit_by>
  local remain_key = buf:reset():put(
    limit_by.remain_segment_0,
    id_seg_1,
    limit_by.remain_segment_1,
    id_seg_2,
    limit_by.remain_segment_3
  ):get()

  rl_ctx[limit_key] = limit
  rl_ctx[remain_key] = remaining
end

function _M.get_basic_limit(ngx_ctx)
  local rl_ctx = _get_rl_ctx(ngx_ctx or ngx.ctx)
  return rl_ctx[RL_LIMIT], rl_ctx[RL_REMAINING], rl_ctx[RL_RESET]
end

function _M.get_retry_after(ngx_ctx)
  local rl_ctx = _get_rl_ctx(ngx_ctx or ngx.ctx)
  return rl_ctx[RETRY_AFTER]
end

function _M.get_limit_by(ngx_ctx, limit_by)
  local rl_ctx = _get_rl_ctx(ngx_ctx or ngx.ctx)

  assert(
    type(limit_by) == "string",
    "arg #2 `limit_by` for `get_limit_by` must be a string"
  )

  limit_by = LIMIT_BY[limit_by]
  assert(limit_by, "invalid limit_by")

  return rl_ctx[limit_by.limit], rl_ctx[limit_by.remain]
end

function _M.get_limit_by_with_identifier(ngx_ctx, limit_by, id_seg_1, id_seg_2)
  local rl_ctx = _get_rl_ctx(ngx_ctx or ngx.ctx)

  assert(
    type(limit_by) == "string",
    "arg #2 `limit_by` for `get_limit_by_with_identifier` must be a string"
  )

  local id_seg_1_typ = type(id_seg_1)
  local id_seg_2_typ = type(id_seg_2)
  assert(
    id_seg_1_typ == "nil" or id_seg_1_typ == "string",
    "arg #3 `id_seg_1` for `get_limit_by_with_identifier` must be a string or nil"
  )
  assert(
    id_seg_2_typ == "nil" or id_seg_2_typ == "string",
    "arg #4 `id_seg_2` for `get_limit_by_with_identifier` must be a string or nil"
  )

  limit_by = LIMIT_BY[limit_by]
  if not limit_by then
    local valid_limit_bys = tablex_keys(LIMIT_BY)
    local msg = string.format(
      "arg #2 `limit_by` for `get_limit_by_with_identifier` must be one of: %s",
      table.concat(valid_limit_bys, ", ")
    )
    error(msg)
  end

  id_seg_1 = id_seg_1 or ""
  id_seg_2 = id_seg_2 or ""

  -- construct the key like X-<id_seg_1>-RateLimit-Limit-<id_seg_2>-<limit_by>
  local limit_key = buf:reset():put(
    limit_by.limit_segment_0,
    id_seg_1,
    limit_by.limit_segment_1,
    id_seg_2,
    limit_by.limit_segment_3
  ):get()

  -- construct the key like X-<id_seg_1>-RateLimit-Remaining-<id_seg_2>-<limit_by>
  local remain_key = buf:reset():put(
    limit_by.remain_segment_0,
    id_seg_1,
    limit_by.remain_segment_1,
    id_seg_2,
    limit_by.remain_segment_3
  ):get()

  return rl_ctx[limit_key], rl_ctx[remain_key]
end

function _M.set_response_headers(ngx_ctx)
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
