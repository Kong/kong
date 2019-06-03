--- Copyright 2019 Kong Inc.


local BasePlugin = require("kong.plugins.base_plugin")
local mtls_cache = require("kong.plugins.mtls-auth.cache")
local access = require("kong.plugins.mtls-auth.access")
local certificate = require("kong.plugins.mtls-auth.certificate")
local kong_global = require("kong.global")


local MtlsAuthHandler = BasePlugin:extend()


function MtlsAuthHandler:access(conf)
  MtlsAuthHandler.super.access(self)

  access.execute(conf)
end


function MtlsAuthHandler:init_worker()
  -- TODO: remove nasty hacks once we have singleton phases support in core

  local orig_ssl_certificate = Kong.ssl_certificate
  Kong.ssl_certificate = function()
    orig_ssl_certificate()

    kong_global.set_namespaced_log(kong, "mtls-auth")
    certificate.execute()
    kong_global.reset_log(kong)
  end

  MtlsAuthHandler.super.init_worker(self)

  mtls_cache.init_worker()
end


MtlsAuthHandler.PRIORITY = 1006
MtlsAuthHandler.VERSION = "0.0.1"


return MtlsAuthHandler
