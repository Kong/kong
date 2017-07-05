local BasePlugin = require "kong.plugins.base_plugin"
local cache      = require "kong.plugins.openid-connect.cache"
local constants  = require "kong.constants"
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
local type       = type
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


local function unauthorized(iss, err)
  if err then
    log(NOTICE, err)
  end
  local parts = uri.parse(iss)
  header["WWW-Authenticate"] = 'Bearer realm="' .. parts.host .. '"'
  return responses.send_HTTP_UNAUTHORIZED()
end


local function consumer(conf, tok, claim, anon)
  if not tok then
    return nil, "token for consumer mapping was not found"
  end

  if type(tok) ~= "table" then
    return nil, "opaque token cannot be used for consumer mapping"
  end

  local payload = tok.payload

  if not payload then
    return nil, "token payload was not found for consumer mapping"
  end

  if type(payload) ~= "table" then
    return nil, "invalid token payload was specified for consumer mapping"
  end

  local subject = payload[claim]

  if not subject then
    return nil, "claim (" .. claim .. ") was not found for consumer mapping"
  end

  return cache.consumers.load(conf, subject, anon)
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
    local parts = uri.parse(iss)
    header["WWW-Authenticate"] = 'Bearer realm="' .. parts.host .. '"'
    return responses.send_HTTP_UNAUTHORIZED()
  end

  local data = s.data
  local toks = data.tokens

  local decoded

  local expires = data.expires - conf.leeway
  if expires > time() then
    s:start()
    if conf.reverify then
      decoded, err = o.token:verify(toks, { nonce = data.nonce, tokens = tokens })
      if not decoded then
        return unauthorized(iss, err)
      end
    end

  else
    if not toks.refresh_token then
      return unauthorized(iss)
    end

    local tks
    local refresh_token = toks.refresh_token
    tks, err = o.token:refresh(refresh_token)

    if not tks then
      return unauthorized(iss, err)
    end

    if not tks.id_token then
      tks.id_token = toks.id_token
    end

    if not tks.refresh_token then
      tks.refresh_token = refresh_token
    end

    decoded, err = o.token:verify(tks, { tokens = tokens })
    if not decoded then
      return unauthorized(iss, err)
    end

    toks = tks

    -- TODO: introspect refreshed tokens?
    -- TODO: call userinfo endpoint to refresh?

    local expires = (tonumber(toks.expires_in) or 3600) + time()

    s.data = {
      tokens  = toks,
      expires = expires,
    }

    s:regenerate()
  end


  local claim = conf.consumer_claim
  if claim and claim ~= "" then
    if not decoded then
      decoded, err = o.token:decode(toks, { tokens = tokens })
      if not decoded then
        return unauthorized(iss, err)
      end
    end

    local consr

    local id_token = decoded.id_token
    if id_token then
      consr, err = consumer(conf, id_token, claim)
      if not consr then
        consr = consumer(conf, decoded.access_token, claim)
      end

    else
      consr, err = consumer(conf, decoded.access_token, claim)
    end

    local is_anonymous = false

    if not consr then
      local anonymous = conf.anonymous
      if anonymous == nil or anonymous == "" then
        if err then
          return unauthorized(iss, "consumer was not found (" .. err .. ")")

        else
          return unauthorized(iss, "consumer was not found")
        end
      end

      is_anonymous = true

      local tok = {
        payload = {
          [claim] = anonymous
        }
      }

      consr, err = consumer(conf, tok, claim, true)
      if not consr then
        if err then
          return unauthorized(iss, "anonymous consumer was not found (" .. err .. ")")

        else
          return unauthorized(iss, "anonymous consumer was not found")
        end
      end
    end

    local headers = constants.HEADERS

    ngx.ctx.authenticated_consumer = consr

    set_header(headers.CONSUMER_ID,        consr.id)
    set_header(headers.CONSUMER_CUSTOM_ID, consr.custom_id)
    set_header(headers.CONSUMER_USERNAME,  consr.username)

    if is_anonymous then
      set_header(headers.ANONYMOUS, is_anonymous)
    end
  end

  s:hide()

  if toks.access_token then
    set_header("Authorization", "Bearer " .. toks.access_token)
  end

  -- TODO: check required scopes
  -- TODO: append jwks to request
  -- TODO: append user info to request
  -- TODO: append id token to request
  -- TODO: require a new authentication when the previous is too far in the past
end


OICProtectionHandler.PRIORITY = 990


return OICProtectionHandler
