local BasePlugin = require "kong.plugins.base_plugin"
local responses  = require "kong.tools.responses"
local session    = require "resty.session"
local oic        = require "kong.openid-connect"


local redirect   = ngx.redirect
local log        = ngx.log


local NOTICE     = ngx.NOTICE
local ERR        = ngx.ERR


local OICAuthenticationHandler = BasePlugin:extend()

function OICAuthenticationHandler:new()
  OICAuthenticationHandler.super.new(self, "openid-connect-authentication")
end


function OICAuthenticationHandler:init_worker()
  OICAuthenticationHandler.super.init_worker(self)
end


function OICAuthenticationHandler:access(conf)
  OICAuthenticationHandler.super.access(self)
  if not self.oic then
    log(NOTICE, "loading openid connect configuration")

    local claims = conf.claims or { "iss", "sub", "aud", "azp", "exp", "iat" }

    local o, err = oic.new {
      client_id     = conf.client_id,
      client_secret = conf.client_secret,
      issuer        = conf.issuer,
      redirect_uri  = conf.redirect_uri,
      scopes        = conf.scopes,
      claims        = claims,
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

  local s, present = session.open()

  if present then
    local data = s.data

    if data.state and data.nonce then
      local err, tokens, encoded
      local args = {
        state = data.state,
        nonce = data.nonce,
      }

      args, err = self.oic.authorization:verify(args)
      if not args then
        log(NOTICE, err)
        s:destroy()
        return responses.send_HTTP_UNAUTHORIZED()
      end

      tokens, err = self.oic.token:request(args)
      if not tokens then
        log(NOTICE, err)
        s:destroy()
        return responses.send_HTTP_UNAUTHORIZED()
      end

      encoded, err = oic.token:verify(tokens, args)
      if not encoded then
        log(NOTICE, err)
        s:destroy()
        return responses.send_HTTP_UNAUTHORIZED()
      end

      s:regenerate()
      s.data = tokens
      s:save()

    else
      s:start()
    end

  else
    local args, err = self.oic.authorization:request()
    if not args then
      log(ERR, err)
      return responses.send_HTTP_INTERNAL_SERVER_ERROR()
    end

    s.data = {
      state = args.state,
      nonce = args.nonce,
    }

    s:save()

    return redirect(args.url)
  end
end


OICAuthenticationHandler.PRIORITY = 1000

return OICAuthenticationHandler
