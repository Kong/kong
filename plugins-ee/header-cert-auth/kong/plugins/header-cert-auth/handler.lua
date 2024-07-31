-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

--- Copyright 2019 Kong Inc.

local meta = require "kong.meta"

local HeaderCertAuthHandler = {
  PRIORITY = 1009,
  VERSION = meta.core_version
}

-- In stream subsystem we don't have functions like ngx.ocsp and
-- get full client chain working. Masking this plugin as a noop
-- plugin so it will not error out.

if ngx.config.subsystem ~= "http" then
    return HeaderCertAuthHandler
end

local cache = require("kong.plugins.header-cert-auth.cache")
local access = require("kong.plugins.header-cert-auth.access")


function HeaderCertAuthHandler:access(conf)
  access.execute(conf)
end


function HeaderCertAuthHandler:init_worker()
  cache.init_worker()
end


return HeaderCertAuthHandler
