local BasePlugin = require "kong.plugins.base_plugin"
local cache      = require "kong.plugins.openid-connect.cache"
local responses  = require "kong.tools.responses"
local oic        = require "kong.openid-connect"
local session    = require "resty.session"


local redirect   = ngx.redirect
local var        = ngx.var
local log        = ngx.log
local tonumber   = tonumber
local concat     = table.concat
local find       = string.find
local type       = type
local sub        = string.sub


local NOTICE     = ngx.NOTICE
local ERR        = ngx.ERR


local function request_url()
  local scheme = var.scheme
  local host   = var.host
  local port   = tonumber(var.server_port)
  local uri    = var.request_uri

  do
    local s = find(uri, "?", 2, true)
    if s then
      uri = sub(uri, 1, s - 1)
    end
  end

  local url = { scheme, "://", host }

  if port == 80 and scheme == "http" then
    url[4] = uri
  elseif port == 443 and scheme == "https" then
    url[4] = uri
  else
    url[4] = ":"
    url[5] = port
    url[6] = uri
  end

  return concat(url)
end


local OICAuthenticationHandler = BasePlugin:extend()


function OICAuthenticationHandler:new()
  OICAuthenticationHandler.super.new(self, "openid-connect-authentication")
end


function OICAuthenticationHandler:init_worker()
  OICAuthenticationHandler.super.init_worker(self)
end


function OICAuthenticationHandler:access(conf)
  OICAuthenticationHandler.super.access(self)

  local issuer, err = cache.issuers.load(conf)
  if not issuer then
    log(ERR, err)
    return responses.send_HTTP_INTERNAL_SERVER_ERROR()
  end
  local o, err = oic.new {
    client_id     = conf.client_id,
    client_secret = conf.client_secret,
    issuer        = conf.issuer,
    redirect_uri  = conf.redirect_uri or request_url(),
    scope         = conf.scopes or { "openid" },
    claims        = conf.claims or { "iss", "sub", "aud", "azp", "exp" },
    leeway        = conf.leeway                     or 0,
    http_version  = conf.http_version               or 1.1,
    ssl_verify    = conf.ssl_verify == nil and true or conf.ssl_verify,
    timeout       = conf.timeout                    or 10000,
    max_age       = conf.max_age,
    domains       = conf.domains,
  }

  local tokens = conf.tokens or { "id_token", "access_token" }

  if not o then
    log(ERR, err)
    return responses.send_HTTP_INTERNAL_SERVER_ERROR()
  end
  local s, present = session.open()

  if present then
    local data = s.data

    if data.state then
      local err, tokens, encoded
      local args = {
        state         = data.state,
        nonce         = data.nonce,
        code_verifier = data.code_verifier,
      }

      args, err = self.oic.authorization:verify(args)
      if not args then
        log(NOTICE, err)
        s:destroy()
        return responses.send_HTTP_UNAUTHORIZED()
      end

      tokens, err = o.token:request(args)
      if not tokens then
        log(NOTICE, err)
        s:destroy()
        return responses.send_HTTP_UNAUTHORIZED()
      end

      encoded, err = o.token:verify(tokens, args)
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
        nonce  = args.nonce,
      }
      s:save()

      if type(encoded.id_token) == "table" then
        return responses.send_HTTP_OK(encoded.id_token.payload or {})

      else
        return responses.send_HTTP_OK{}
      end
    else
      local encoded, err = o.token:verify(data.tokens, { nonce = data.nonce, tokens = tokens })
      if not encoded then
        log(NOTICE, err)
        s:destroy()
        return responses.send_HTTP_UNAUTHORIZED()

      else
        s:start()
        return responses.send_HTTP_OK(data.tokens.id_token or {})
      end
    end

  else
    local args, err = o.authorization:request()
    if not args then
      log(ERR, err)
      return responses.send_HTTP_INTERNAL_SERVER_ERROR()
    end

    s.data = {
      state         = args.state,
      nonce         = args.nonce,
      code_verifier = args.code_verifier,
    }

    s:save()

    return redirect(args.url)
  end
end


OICAuthenticationHandler.PRIORITY = 1000


return OICAuthenticationHandler
