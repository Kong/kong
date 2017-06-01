local BasePlugin = require "kong.plugins.base_plugin"
local responses  = require "kong.tools.responses"
local oic        = require "kong.openid-connect"
local session    = require "resty.session"


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

    local o, err = oic.new {
      client_id     = conf.client_id,
      client_secret = conf.client_secret,
      issuer        = conf.issuer,
      redirect_uri  = conf.redirect_uri,
      scope         = conf.scopes or { "openid" },
      claims        = conf.claims or { "iss", "sub", "aud", "azp", "exp", "iat" },
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

      encoded, err = self.oic.token:verify(tokens, args)
      if not encoded then
        log(NOTICE, err)
        s:destroy()
        return responses.send_HTTP_UNAUTHORIZED()
      end

      -- TODO: introspect tokens
      -- TODO: call userinfo endpoint

      s:regenerate()
      s.data = {
        tokens = tokens,
        nonce  = args.nonce
      }
      s:save()

      return responses.send_HTTP_OK(encoded.id_token.payload)
    else
      local encoded, err = self.oic.token:verify(data.tokens, { nonce = data.nonce })
      if not encoded then
        log(NOTICE, err)
        s:destroy()
        return responses.send_HTTP_UNAUTHORIZED()
      else
        s:start()
        -- TODO: proxy the request
        -- TODO: append access token as a bearer token
        -- TODO: append jwk to header
        -- TODO: handle refreshing the access token
        -- TODO: require a new authentication when the previous is too far in the past
        return responses.send_HTTP_OK { logged = "in" }
      end
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
