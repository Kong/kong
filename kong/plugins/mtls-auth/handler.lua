-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

--- Copyright 2019 Kong Inc.

-- In http subsystem we don't have functions like ngx.ocsp and
-- get full client chain working. Masking this plugin as a noop
-- plugin so it will not error out.
if ngx.config.subsystem ~= "http" then
    return {}
end

local mtls_cache = require("kong.plugins.mtls-auth.cache")
local access = require("kong.plugins.mtls-auth.access")
local certificate = require("kong.plugins.mtls-auth.certificate")
local kong_global = require("kong.global")
local PHASES = kong_global.phases


local MtlsAuthHandler = {
  PRIORITY = 1006,
  VERSION = "0.3.3"
}


function MtlsAuthHandler:access(conf)
  access.execute(conf)
end


function MtlsAuthHandler:init_worker()
  -- TODO: remove nasty hacks once we have singleton phases support in core

  local orig_ssl_certificate = Kong.ssl_certificate
  Kong.ssl_certificate = function()
    orig_ssl_certificate()

    -- ensure phases are set
    kong_global.set_phase(kong, PHASES.certificate)

    kong_global.set_namespaced_log(kong, "mtls-auth")
    certificate.execute()
    kong_global.reset_log(kong)
  end

  mtls_cache.init_worker()
end


return MtlsAuthHandler
