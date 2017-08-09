local BasePlugin    = require "kong.plugins.base_plugin"
local cache         = require "kong.plugins.openid-connect.cache"
local responses     = require "kong.tools.responses"
local oic           = require "kong.openid-connect"
local uri           = require "kong.openid-connect.uri"
local session       = require "resty.session"


local redirect      = ngx.redirect
local var           = ngx.var
local log           = ngx.log
local time          = ngx.time
local header        = ngx.header
local read_body     = ngx.req.read_body
local get_uri_args  = ngx.req.get_uri_args
local get_post_args = ngx.req.get_post_args
local tonumber      = tonumber
local concat        = table.concat
local find          = string.find
local type          = type
local sub           = string.sub


local NOTICE        = ngx.NOTICE
local ERR           = ngx.ERR


local function request_url()
  local scheme = var.scheme
  local host   = var.host
  local port   = tonumber(var.server_port)
  local u      = var.request_uri

  do
    local s = find(u, "?", 2, true)
    if s then
      u = sub(u, 1, s - 1)
    end
  end

  local url = { scheme, "://", host }

  if port == 80 and scheme == "http" then
    url[4] = u
  elseif port == 443 and scheme == "https" then
    url[4] = u
  else
    url[4] = ":"
    url[5] = port
    url[6] = u
  end

  return concat(url)
end


local function unauthorized(iss, err, s)
  if err then
    log(NOTICE, err)
  end

  if s then
    s:destroy()
  end

  local parts = uri.parse(iss)
  header["WWW-Authenticate"] = 'Bearer realm="' .. parts.host .. '"'
  return responses.send_HTTP_UNAUTHORIZED()
end


local function unexpected(err)
  if err then
    log(ERR, err)
  end

  return responses.send_HTTP_INTERNAL_SERVER_ERROR()
end


local function success(response)
  return responses.send_HTTP_OK(response)
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
    return unexpected(err)
  end

  local iss    = o.configuration.issuer
  local tokens = conf.tokens or { "id_token", "access_token" }

  local s, session_present = session.open { secret = issuer.secret }

  if not session_present then
    local authorization, authorization_present = session.open {
      name   = "authorization",
      secret = issuer.secret,
      cookie = {
        samesite = "off",
      }
    }

    if not authorization_present then
      local args
      args, err = o.authorization:request()
      if not args then
        return unexpected(err)
      end

      authorization.data = {
        state         = args.state,
        nonce         = args.nonce,
        code_verifier = args.code_verifier,
      }

      authorization:save()

      return redirect(args.url)
    end

    local authorization_data = authorization.data or {}
    local state = authorization_data.state

    if state then
      local toks, decoded
      local args = {
        state         = authorization_data.state,
        nonce         = authorization_data.nonce,
        code_verifier = authorization_data.code_verifier,
      }

      local uri_args = get_uri_args()

      args, err = o.authorization:verify(args)
      if not args then
        if uri_args.state == state then
          log(ERR, "a")
          return unauthorized(iss, err, authorization)

        else
          read_body()
          local post_args = get_post_args()
          if post_args.state == state then
            log(ERR, "b")
            return unauthorized(iss, err, authorization)
          end
        end

        log(ERR, "c")
        return unauthorized(iss, err)
      end

      authorization:destroy()

      toks, err = o.token:request(args)
      if not toks then
        log(ERR, "d")
        return unauthorized(iss, err)
      end

      decoded, err = o.token:verify(toks, args)
      if not decoded then
        log(ERR, "e")
        return unauthorized(iss, err)
      end

      -- TODO: introspect tokens
      -- TODO: call userinfo endpoint

      local expires = (tonumber(toks.expires_in) or 3600) + time()

      s.data    = {
        tokens  = toks,
        expires = expires,
      }

      s:save()

      local login_uri = conf.login_redirect_uri
      if login_uri then
        return redirect(login_uri .. "#id_token=" .. toks.id_token)

      else
        if type(decoded.id_token) == "table" then
          return success { id_token = toks.id_token }

        else
          return success {}
        end
      end
    end
  end

  local data = s.data      or {}
  local toks = data.tokens or {}

  local decoded
  decoded, err = o.token:verify(toks, { tokens = tokens })
  if not decoded then
    return unauthorized(iss, err, s)

  else
    s:start()

    local login_uri = conf.login_redirect_uri
    if login_uri then
      return redirect(login_uri .. "#id_token=" .. toks.id_token)

    else
      return success { id_token = toks.id_token }
    end
  end
end


OICAuthenticationHandler.PRIORITY = 1000


return OICAuthenticationHandler
