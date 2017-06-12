local BasePlugin = require "kong.plugins.base_plugin"
local cache      = require "kong.plugins.openid-connect.cache"
local responses  = require "kong.tools.responses"
local oic        = require "kong.openid-connect"
local uri        = require "kong.openid-connect.uri"
local session    = require "resty.session"


local ngx        = ngx
local var        = ngx.var
local log        = ngx.log
local time       = ngx.time
local header     = ngx.header
local set_header = ngx.req.set_header
local tonumber   = tonumber
local concat     = table.concat
local find       = string.find
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

  local iss    = o.configuration.issuer
  local tokens = conf.tokens or { "id_token", "access_token" }

  -- TODO: Add support for session configuration
  local s, present = session.open()

  if present then
    local data    = s.data
    local toks    = data.tokens
    local expires = data.expires - conf.leeway
    if expires < time() then
      if toks.refresh_token then
        local toks, err = oic.token:refresh(toks.refresh_token)
        if toks then
          local expires = (tonumber(toks.expires_in) or 3600) + time()
          local decoded

          decoded, err = o.token:verify(toks, { nonce = data.nonce, tokens = tokens })
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
            nonce   = data.nonce,
          }
          s:regenerate()
          s:hide()

          if toks.access_token then
            set_header("Authorization", "Bearer " .. toks.access_token)
          end
          -- TODO: check required scopes
          -- TODO: append jwks to request
          -- TODO: append user info to request
          -- TODO: append id token to request
          -- TODO: require a new authentication when the previous is too far in the past

        else
          log(NOTICE, err)
          local parts = uri.parse(iss)
          header["WWW-Authenticate"] = 'Bearer realm="' .. parts.host .. '"'
          return responses.send_HTTP_UNAUTHORIZED()
        end

      else
        local parts = uri.parse(iss)
        header["WWW-Authenticate"] = 'Bearer realm="' .. parts.host .. '"'
        return responses.send_HTTP_UNAUTHORIZED()
      end

    else
      local decoded, err = o.token:verify(toks, { nonce = data.nonce, tokens = tokens })
      if decoded then
        s:start()
        s:hide()
        if toks.access_token then
          set_header("Authorization", "Bearer " .. toks.access_token)
        end
        -- TODO: check required scopes
        -- TODO: append jwks to request
        -- TODO: append user info to request
        -- TODO: append id token to request
        -- TODO: require a new authentication when the previous is too far in the past

      else
        log(NOTICE, err)
        local parts = uri.parse(iss)
        header["WWW-Authenticate"] = 'Bearer realm="' .. parts.host .. '"'
        return responses.send_HTTP_UNAUTHORIZED()
      end
    end

  else
    local parts = uri.parse(iss)
    header["WWW-Authenticate"] = 'Bearer realm="' .. parts.host .. '"'
    return responses.send_HTTP_UNAUTHORIZED()
  end
end


OICProtectionHandler.PRIORITY = 950


return OICProtectionHandler
