local BasePlugin = require "kong.plugins.base_plugin"
local cache      = require "kong.plugins.openid-connect.cache"
local responses  = require "kong.tools.responses"
local oic        = require "kong.openid-connect"
local session    = require "resty.session"


local log        = ngx.log


local NOTICE     = ngx.NOTICE
local ERR        = ngx.ERR


local OICProtectionHandler = BasePlugin:extend()

function OICProtectionHandler:new()
  OICProtectionHandler.super.new(self, "openid-connect-protection")
end


function OICProtectionHandler:init_worker()
  OICProtectionHandler.super.init_worker(self)
end


function OICProtectionHandler:access(conf)
  OICProtectionHandler.super.access(self)

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

  local s, present = session.open()

  if present then
    local data = s.data

    local encoded, err = o.token:verify(data.tokens, { nonce = data.nonce })
    if not encoded then
      log(NOTICE, err)
      s:destroy()
      return responses.send_HTTP_UNAUTHORIZED()
    else
      -- TODO: check required scopes

      s:start() -- TODO: move this to header_filter
      -- TODO: append access token as a bearer token
      -- TODO: append jwk to header
      -- TODO: handle refreshing the access token
      -- TODO: require a new authentication when the previous is too far in the past
    end

  else
    -- TODO: add WWW-Authenticate header
    return responses.send_HTTP_UNAUTHORIZED()
  end
end


OICProtectionHandler.PRIORITY = 1000


return OICProtectionHandler
