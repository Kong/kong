local BasePlugin = require "kong.plugins.base_plugin"
local responses  = require "kong.tools.responses"
local oic        = require "kong.openid-connect"


local log        = ngx.log


local NOTICE     = ngx.NOTICE
local ERR        = ngx.ERR


local OICDereferencingMicroserviceHandler = BasePlugin:extend()

function OICDereferencingMicroserviceHandler:new()
  OICDereferencingMicroserviceHandler.super.new(self, "openid-connect-dereferencing-microservice")
end


function OICDereferencingMicroserviceHandler:init_worker()
  OICDereferencingMicroserviceHandler.super.init_worker(self)
end


function OICDereferencingMicroserviceHandler:access(conf)
  OICDereferencingMicroserviceHandler.super.access(self)
  if not self.oic then
    log(NOTICE, "loading openid connect configuration")

    local o, err = oic.new {
      issuer        = conf.issuer,
      scope         = conf.scopes or { "openid" },
      claims        = conf.claims or { "iss", "sub", "aud", "azp", "exp" },
      leeway        = conf.leeway                     or 0,
      http_version  = conf.http_version               or 1.1,
      ssl_verify    = conf.ssl_verify == nil and true or conf.ssl_verify,
      timeout       = conf.timeout                    or 10000,
      max_age       = conf.max_age,
      domains       = conf.domains,
    }

    if not o then
      log(ERR, err)
      return responses.send_HTTP_INTERNAL_SERVER_ERROR()
    end

    self.oic = o
  end
end


OICDereferencingMicroserviceHandler.PRIORITY = 1000


return OICDereferencingMicroserviceHandler
