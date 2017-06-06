local BasePlugin = require "kong.plugins.base_plugin"
local cache      = require "kong.plugins.openid-connect.cache"
local responses  = require "kong.tools.responses"
local oic        = require "kong.openid-connect"


local log        = ngx.log


local NOTICE     = ngx.NOTICE
local ERR        = ngx.ERR


local OICMicroserviceHandler = BasePlugin:extend()

function OICMicroserviceHandler:new()
  OICMicroserviceHandler.super.new(self, "openid-connect-microservice")
end


function OICMicroserviceHandler:init_worker()
  OICMicroserviceHandler.super.init_worker(self)
end


function OICMicroserviceHandler:access(conf)
  OICMicroserviceHandler.super.access(self)

  local issuer, err = cache.issuers.load(conf)
  if not issuer then
    log(ERR, err)
    return responses.send_HTTP_INTERNAL_SERVER_ERROR()
  end

  local o, err = oic.new({
    issuer        = conf.issuer,
    scope         = conf.scopes or { "openid" },
    claims        = conf.claims or { "iss", "sub", "aud", "azp", "exp" },
    leeway        = conf.leeway                     or 0,
    http_version  = conf.http_version               or 1.1,
    ssl_verify    = conf.ssl_verify == nil and true or conf.ssl_verify,
    timeout       = conf.timeout                    or 10000,
    max_age       = conf.max_age,
    domains       = conf.domains,
  }, issuer.configuration, issuer.keys)

  if not o then
    log(ERR, err)
    return responses.send_HTTP_INTERNAL_SERVER_ERROR()
  end

end


OICMicroserviceHandler.PRIORITY = 1000


return OICMicroserviceHandler
