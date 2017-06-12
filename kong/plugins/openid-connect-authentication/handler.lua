local BasePlugin = require "kong.plugins.base_plugin"
local cache      = require "kong.plugins.openid-connect.cache"
local responses  = require "kong.tools.responses"
local oic        = require "kong.openid-connect"
local session    = require "resty.session"


local redirect   = ngx.redirect
local var        = ngx.var
local log        = ngx.log
local time       = ngx.time
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
  local o, err = oic.new({
    client_id     = conf.client_id,
    client_secret = conf.client_secret,
    redirect_uri  = conf.redirect_uri or request_url(),
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

  local tokens     = conf.tokens or { "id_token", "access_token" }

  -- TODO: Add support for session configuration
  local s, present = session.open()

  if present then
    local data = s.data

    if data.state then
      local err, toks, decoded
      local args = {
        state         = data.state,
        nonce         = data.nonce,
        code_verifier = data.code_verifier,
      }

      args, err = o.authorization:verify(args)
      if not args then
        log(NOTICE, err)
        s:destroy()
        return responses.send_HTTP_UNAUTHORIZED()
      end

      toks, err = o.token:request(args)
      if not toks then
        log(NOTICE, err)
        s:destroy()
        return responses.send_HTTP_UNAUTHORIZED()
      end

      local expires = (tonumber(toks.expires_in) or 3600) + time()

      decoded, err = o.token:verify(toks, args)
      if not decoded then
        log(NOTICE, err)
        s:destroy()
        return responses.send_HTTP_UNAUTHORIZED()
      end

      -- TODO: introspect tokens
      -- TODO: call userinfo endpoint

      s.data = {
        tokens  = toks,
        expires = expires,
        nonce   = args.nonce,
      }
      s:regenerate()

      local login_uri = conf.login_redirect_uri

      if login_uri then
        return redirect(login_uri .. "#id_token=" .. toks.id_token)

      else
        if type(decoded.id_token) == "table" then
          return responses.send_HTTP_OK(toks.id_token or {})

        else
          return responses.send_HTTP_OK{}
        end
      end
    else
      local toks = data.tokens or {}

      local decoded, err = o.token:verify(toks, { nonce = data.nonce, tokens = tokens })
      if not decoded then
        log(NOTICE, err)
        s:destroy()
        return responses.send_HTTP_UNAUTHORIZED()

      else
        s:start()

        local login_uri = conf.login_redirect_uri

        if login_uri then
          return redirect(login_uri .. "#id_token=" .. toks.id_token)

        else
          return responses.send_HTTP_OK(toks.id_token or {})
        end
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
