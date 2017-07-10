local BasePlugin = require "kong.plugins.base_plugin"
local cache      = require "kong.plugins.openid-connect.cache"
local responses  = require "kong.tools.responses"
local codec      = require "kong.openid-connect.codec"
local oic        = require "kong.openid-connect"


local base64url  = codec.base64url
--local json       = codec.json
local log        = ngx.log


local ERR        = ngx.ERR


local OICDereferencingHandler = BasePlugin:extend()

function OICDereferencingHandler:new()
  OICDereferencingHandler.super.new(self, "openid-connect-dereferencing")
end


function OICDereferencingHandler:init_worker()
  OICDereferencingHandler.super.init_worker(self)
end


function OICDereferencingHandler:access(conf)
  OICDereferencingHandler.super.access(self)

  local issuer, err = cache.issuers.load(conf)
  if not issuer then
    log(ERR, err)
    return responses.send_HTTP_INTERNAL_SERVER_ERROR()
  end

  local o

  o, err = oic.new({
    leeway        = conf.leeway                     or 0,
    http_version  = conf.http_version               or 1.1,
    ssl_verify    = conf.ssl_verify == nil and true or conf.ssl_verify,
    timeout       = conf.timeout                    or 10000,
  }, issuer.configuration, issuer.keys)

  if not o then
    log(ERR, err)
    return responses.send_HTTP_INTERNAL_SERVER_ERROR()
  end

  local act = oic.token:bearer()

  if act then
    local userinfo
    userinfo, err = o:userinfo()
    if userinfo then
      base64url.encode(userinfo)

    else
      log(ERR, err)
    end
  end
end


OICDereferencingHandler.PRIORITY = 970


return OICDereferencingHandler
