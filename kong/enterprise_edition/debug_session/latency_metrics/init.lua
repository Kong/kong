-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local ngx_get_phase = ngx.get_phase


local VALID_PHASES = {
  ssl_cert = true,
  rewrite = true,
  access = true,
  header_filter = true,
  body_filter = true,
  log = true,
  content = true,
  balancer = true,
}

local function init_latency_metrics_ctx()
  local lmctx = ngx.ctx.latency_metrics
  if not lmctx then
    lmctx = {}
    ngx.ctx.latency_metrics = lmctx
  end
  return lmctx
end


local _M = {}


function _M.is_valid_phase()
  local phase = ngx_get_phase()
  return VALID_PHASES[phase]
end

function _M.get(key)
  assert(key, "key is required")

  if not _M.is_valid_phase() then
    return nil, "invalid phase"
  end

  local lmctx = init_latency_metrics_ctx()
  return lmctx[key] or 0
end


function _M.set(key, value)
  assert(key, "key is required")
  assert(value, "value is required")
  assert(type(value) == "number", "value must be a number")

  if not _M.is_valid_phase() then
    return nil, "invalid phase"
  end

  local lmctx = init_latency_metrics_ctx()
  lmctx[key] = value
  return true
end


function _M.add(key, value)
  assert(key, "key is required")
  assert(value, "value is required")
  assert(type(value) == "number", "value must be a number")

  if not _M.is_valid_phase() then
    return nil, "invalid phase"
  end

  local lmctx = init_latency_metrics_ctx()
  lmctx[key] = _M.get(key) + value
  return lmctx[key]
end


return _M
