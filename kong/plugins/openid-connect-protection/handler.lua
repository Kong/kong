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


local function unauthorized(issuer, err, s)
  if err then
    log(NOTICE, err)
  end

  if s then
    s:destroy()
  end

  local parts = uri.parse(issuer)
  header["WWW-Authenticate"] = 'Bearer realm="' .. parts.host .. '"'
  return responses.send_HTTP_UNAUTHORIZED()
end


local function forbidden(issuer, err, s)
  if err then
    log(NOTICE, err)
  end

  if s then
    s:destroy()
  end

  local parts = uri.parse(issuer)
  header["WWW-Authenticate"] = 'Bearer realm="' .. parts.host .. '"'
  return responses.send_HTTP_FORBIDDEN()
end



local function consumer(tok, claim, anon, consumer_by)
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

  return cache.consumers.load(subject, anon, consumer_by)
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

  if ngx.ctx.authenticated_credential and conf.anonymous ~= ngx.null and conf.anonymous ~= "" then
    -- we're already authenticated, and we're configured for using anonymous,
    -- hence we're in a logical OR between auth methods and we're already done.
    return
  end

  local issuer, err = cache.issuers.load(conf.issuer)
  if not issuer then
    log(ERR, err)
    return responses.send_HTTP_INTERNAL_SERVER_ERROR()
  end

  local o

  o, err = oic.new({
    client_id         = conf.client_id,
    client_secret     = conf.client_secret,
    redirect_uri      = conf.redirect_uri or request_url(),
    scope             = conf.scopes       or { "openid" },
    audience          = conf.audience,
    domains           = conf.domains,
    max_age           = conf.max_age,
    timeout           = conf.timeout      or 10000,
    leeway            = conf.leeway       or 0,
    http_version      = conf.http_version or 1.1,
    ssl_verify        = conf.ssl_verify == nil and true or conf.ssl_verify,
    verify_parameters = conf.verify_parameters,
    verify_nonce      = conf.verify_nonce,
    verify_signature  = conf.verify_signature,
    verify_claims     = conf.verify_claims,
  }, issuer.configuration, issuer.keys)

  if not o then
    log(ERR, err)
    return responses.send_HTTP_INTERNAL_SERVER_ERROR()
  end

  local iss = o.configuration.issuer

  -- TODO: Add support for session configuration (currently possible through nginx configuration)
  local s, session_present = session.open { secret = issuer.secret }

  if not session_present then
    return unauthorized(iss, "openid connect authenticated session was not present")
  end

  local data = s.data
  local tokens_encoded = data.tokens
  local tokens_decoded
  local default_expires_in = 3600
  local now = time()

  local expires = (data.expires or conf.leeway) - conf.leeway
  if expires > time() then
    s:start()
    if conf.reverify then
      tokens_decoded, err = o.token:verify(tokens_encoded)
      if not tokens_decoded then
        return forbidden(iss, err)
      end
    end

  else
    if not tokens_encoded.refresh_token then
      return forbidden(iss, "access token cannot be refreshed in absense of refresh token", s)
    end

    local tokens_refreshed
    local refresh_token = tokens_encoded.refresh_token
    tokens_refreshed, err = o.token:refresh(refresh_token)

    if not tokens_refreshed then
      return forbidden(iss, err, s)
    end

    if not tokens_refreshed.id_token then
      tokens_refreshed.id_token = tokens_encoded.id_token
    end

    if not tokens_refreshed.refresh_token then
      tokens_refreshed.refresh_token = refresh_token
    end

    tokens_decoded, err = o.token:verify(tokens_refreshed)
    if not tokens_decoded then
      return forbidden(iss, err, s)
    end

    tokens_encoded = tokens_refreshed

    expires = (tonumber(tokens_encoded.expires_in) or default_expires_in) + now

    s.data = {
      tokens  = tokens_encoded,
      expires = expires,
    }

    s:regenerate()

  end

  local consumer_claim = conf.consumer_claim
  if consumer_claim and consumer_claim ~= "" then
    local consumer_by = conf.consumer_by

    if not tokens_decoded then
      tokens_decoded, err = o.token:decode(tokens_encoded)
    end

    local mapped_consumer

    if tokens_decoded then
      local id_token = tokens_decoded.id_token
      if id_token then
        mapped_consumer, err = consumer(id_token, consumer_claim, false, consumer_by)
        if not mapped_consumer then
          mapped_consumer = consumer(tokens_decoded.access_token, consumer_claim, false, consumer_by)
        end

      else
        mapped_consumer, err = consumer(tokens_decoded.access_token, consumer_claim, false, consumer_by)
      end
    end

    local is_anonymous = false

    if not mapped_consumer then
      local anonymous = conf.anonymous
      if anonymous == nil or anonymous == "" then
        if err then
          return forbidden(iss, "consumer was not found (" .. err .. ")", s)

        else
          return forbidden(iss, "consumer was not found", s)
        end
      end

      is_anonymous = true

      local consumer_token = {
        payload = {
          [consumer_claim] = anonymous
        }
      }

      mapped_consumer, err = consumer(consumer_token, consumer_claim, true, consumer_by)
      if not mapped_consumer then
        if err then
          return forbidden(iss, "anonymous consumer was not found (" .. err .. ")", s)

        else
          return forbidden(iss, "anonymous consumer was not found", s)
        end
      end
    end

    local headers = constants.HEADERS

    ngx.ctx.authenticated_consumer = mapped_consumer
    ngx.ctx.authenticated_credential = {
      consumer_id = mapped_consumer.id
    }

    set_header(headers.CONSUMER_ID,        mapped_consumer.id)
    set_header(headers.CONSUMER_CUSTOM_ID, mapped_consumer.custom_id)
    set_header(headers.CONSUMER_USERNAME,  mapped_consumer.username)

    if is_anonymous then
      set_header(headers.ANONYMOUS, is_anonymous)
    end
  end

  s:hide()

  if tokens_encoded.access_token then
    set_header("Authorization", "Bearer " .. tokens_encoded.access_token)
  end

  -- TODO: check required scopes
  -- TODO: append jwks to request
  -- TODO: append user info to request
  -- TODO: append id token to request
  -- TODO: require a new authentication when the previous is too far in the past
end


OICProtectionHandler.PRIORITY = 990
OICProtectionHandler.VERSION  = cache.version


return OICProtectionHandler
