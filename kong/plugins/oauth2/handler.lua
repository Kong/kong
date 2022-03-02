-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local access = require "kong.plugins.oauth2.access"


-- TODO version differs from CE and should be fixed in 3.0
-- https://github.com/Kong/kong-ee/commit/0bcc424bee6553bbc3cd41452d807a20027afb56
local OAuthHandler = {
  PRIORITY = 1004,
  VERSION = "2.2.1",
}


function OAuthHandler:access(conf)
  access.execute(conf)
end


return OAuthHandler
