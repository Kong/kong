-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local kset_next_upstream
if ngx.config.subsystem ~= "stream" then
  kset_next_upstream = require("resty.kong.upstream").set_next_upstream
end

local ngx = ngx
local log = ngx.log
local ERR = ngx.ERR

local function set_proxy_next_upstream(next_upstream)
  local err = kset_next_upstream(unpack(next_upstream))
  if err then
    log(ERR, "failed to set next upstream: ", err)
  end

  if ngx.ctx and ngx.ctx.balancer_data then
    ngx.ctx.balancer_data.next_upstream = next_upstream
  end
end

local function fallback_proxy_next_upstream()
  if not ngx.ctx.balancer_data then
    return
  end

  if not ngx.ctx.balancer_data.next_upstream then
    return
  end

  local err = kset_next_upstream(unpack(ngx.ctx.balancer_data.next_upstream))
  if err then
    log(ERR, "failed to set next upstream: ", err)
  end
end

return {
  set_proxy_next_upstream = set_proxy_next_upstream,
  fallback_proxy_next_upstream = fallback_proxy_next_upstream,
}
