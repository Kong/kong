-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

-- a plugin fixture to test running of the rewrite phase handler.

local BasePlugin = require "kong.plugins.base_plugin"

local Rewriter = BasePlugin:extend()

Rewriter.PRIORITY = 1000

function Rewriter:new()
  Rewriter.super.new(self, "rewriter")
end

function Rewriter:rewrite(conf)
  Rewriter.super.access(self)

  ngx.req.set_header("rewriter", conf.value)
end

return Rewriter
