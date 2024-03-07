-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local meta = require "kong.meta"


local UpstreamTimeout = {}

function UpstreamTimeout:access(conf)
  -- Needs option to revert to old timeout
  if conf.read_timeout then
    ngx.ctx.balancer_data.read_timeout = conf.read_timeout
  end
  if conf.send_timeout then
    ngx.ctx.balancer_data.send_timeout = conf.send_timeout
  end
  if conf.connect_timeout then
    ngx.ctx.balancer_data.connect_timeout = conf.connect_timeout
  end

end

UpstreamTimeout.PRIORITY = 400
UpstreamTimeout.VERSION = meta.core_version

return UpstreamTimeout
