-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]


local ngx_log = ngx.log
local ACTIVE_TRACING_CTX_NS = "ACTIVE_TRACING"


local function get_ctx_key(name)
  return ACTIVE_TRACING_CTX_NS .. "_" .. name
end

local function log(level, ...)
  ngx_log(level, "[active_tracing] ", ...)
end


return {
  get_ctx_key = get_ctx_key,
  log = log,
  ctx_namespace = ACTIVE_TRACING_CTX_NS,
}
