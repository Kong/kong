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

  local issuer, err = cache.issuers.load(conf.issuer)
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

  local iss = o.configuration.issuer

  local s, session_present = session.open { secret = issuer.secret }

  if not session_present then
    local authorization, authorization_present = session.open {
      name   = "authorization",
      secret = issuer.secret,
      cookie = {
        samesite = "off",
      }
    }

    if authorization_present then
      local authorization_data = authorization.data or {}

      local state = authorization_data.state

      if state then
        local nonce         = authorization_data.nonce
        local code_verifier = authorization_data.code_verifier

        -- authorization code response
        local args = {
          state         = state,
          nonce         = nonce,
          code_verifier = code_verifier,
        }

        local uri_args = get_uri_args()

        args, err = o.authorization:verify(args)
        if not args then
          if uri_args.state == state then
            return unauthorized(iss, err, authorization)

          else
            read_body()
            local post_args = get_post_args()
            if post_args.state == state then
              return unauthorized(iss, err, authorization)
            end
          end

          -- it seems that user may have opened a second tab
          -- lets redirect that to idp as well in case user
          -- had closed the previous, but with same parameters
          -- as before.
          authorization:start()

          args, err = o.authorization:request {
            state         = state,
            nonce         = nonce,
            code_verifier = code_verifier
          }

          if not args then
            return unexpected(err)
          end

          return redirect(args.url)
        end

        authorization:destroy()

        local tokens_encoded
        tokens_encoded, err = o.token:request(args)
        if not tokens_encoded then
          return unauthorized(iss, err)
        end

        local tokens_decoded
        tokens_decoded, err = o.token:verify(tokens_encoded, args)
        if not tokens_decoded then
          return unauthorized(iss, err)
        end

        local expires = (tonumber(tokens_encoded.expires_in) or 3600) + time()

        s.data    = {
          tokens  = tokens_encoded,
          expires = expires,
        }

        s:save()

        local login_uri = conf.login_redirect_uri
        if login_uri then
          return redirect(login_uri .. "#id_token=" .. tokens_encoded.id_token)

        else
          if type(tokens_decoded.id_token) == "table" then
            return success { id_token = tokens_encoded.id_token }

          else
            return success {}
          end
        end
      end
    end

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

  local data = s.data      or {}
  local toks = data.tokens or {}

  s:start()

  local login_uri = conf.login_redirect_uri
  if login_uri then
    return redirect(login_uri .. "#id_token=" .. toks.id_token)

  else
    return success { id_token = toks.id_token }
  end
end


OICAuthenticationHandler.PRIORITY = 1000
OICAuthenticationHandler.VERSION  = cache.version


return OICAuthenticationHandler
