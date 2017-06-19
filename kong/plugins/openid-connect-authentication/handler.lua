local BasePlugin = require "kong.plugins.base_plugin"
local cache      = require "kong.plugins.openid-connect.cache"
local responses  = require "kong.tools.responses"
local oic        = require "kong.openid-connect"
local uri        = require "kong.openid-connect.uri"
local session    = require "resty.session"


local redirect   = ngx.redirect
local var        = ngx.var
local log        = ngx.log
local time       = ngx.time
local header     = ngx.header
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


local function unauthorized(session, iss, err)
  if err then
    log(NOTICE, err)
  end

  session:destroy()

  local parts = uri.parse(iss)
  header["WWW-Authenticate"] = 'Bearer realm="' .. parts.host .. '"'
  return responses.send_HTTP_UNAUTHORIZED()
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

  local o

  o, err = oic.new({
    client_id     = conf.client_id,
    client_secret = conf.client_secret,
    redirect_uri  = conf.redirect_uri or request_url(),
    scope         = conf.scopes       or { "openid" },
    claims        = conf.claims       or { "iss", "sub", "aud", "azp", "exp" },
    audience      = conf.audience,
    domains       = conf.domains,
    max_age       = conf.max_age,
    timeout       = conf.timeout      or 10000,
    leeway        = conf.leeway       or 0,
    http_version  = conf.http_version or 1.1,
    ssl_verify    = conf.ssl_verify == nil and true or conf.ssl_verify,
  }, issuer.configuration, issuer.keys)

  if not o then
    log(ERR, err)
    return responses.send_HTTP_INTERNAL_SERVER_ERROR()
  end

  local iss    = o.configuration.issuer
  local tokens = conf.tokens or { "id_token", "access_token" }

  -- TODO: Add support for session configuration (currently possible through nginx configuration)
  local s, present = session.open()

  if not present then
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

  local data = s.data

  if data.state then
    local toks, decoded
    local args = {
      state         = data.state,
      nonce         = data.nonce,
      code_verifier = data.code_verifier,
    }

    args, err = o.authorization:verify(args)
    if not args then
      return unauthorized(s, iss, err)
    end

    toks, err = o.token:request(args)
    if not toks then
      return unauthorized(s, iss, err)
    end

    decoded, err = o.token:verify(toks, args)
    if not decoded then
      return unauthorized(s, iss, err)
    end

    -- TODO: introspect tokens
    -- TODO: call userinfo endpoint

    local expires = (tonumber(toks.expires_in) or 3600) + time()

    s.data = {
      tokens  = toks,
      expires = expires,
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
  end

  local toks = data.tokens or {}

  local decoded, err = o.token:verify(toks, { nonce = data.nonce, tokens = tokens })
  if not decoded then
    return unauthorized(s, iss, err)

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


OICAuthenticationHandler.PRIORITY = 1000


return OICAuthenticationHandler
