-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local BasePlugin = require "kong.plugins.base_plugin"


local SlowQueryHandler = BasePlugin:extend()


SlowQueryHandler.PRIORITY = 1000


function SlowQueryHandler:new()
  SlowQueryHandler.super.new(self, "slow-query")
end


return SlowQueryHandler
