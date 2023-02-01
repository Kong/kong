-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local access = require "kong.plugins.session.access"
local header_filter = require "kong.plugins.session.header_filter"
local kong_meta = require "kong.meta"


local KongSessionHandler = {
  PRIORITY = 1900,
  VERSION = kong_meta.core_version,
}


function KongSessionHandler:header_filter(conf)
  header_filter.execute(conf)
end


function KongSessionHandler:access(conf)
  access.execute(conf)
end


return KongSessionHandler
