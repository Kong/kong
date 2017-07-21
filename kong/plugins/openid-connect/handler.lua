local BasePlugin   = require "kong.plugins.base_plugin"
local cache        = require "kong.plugins.openid-connect.cache"
local constants    = require "kong.constants"
local responses    = require "kong.tools.responses"
local oic          = require "kong.openid-connect"
local uri          = require "kong.openid-connect.uri"
local set          = require "kong.openid-connect.set"
local codec        = require "kong.openid-connect.codec"
local session      = require "resty.session"
local upload       = require "resty.upload"


local ngx           = ngx
local redirect      = ngx.redirect
local var           = ngx.var
local log           = ngx.log
local time          = ngx.time
local header        = ngx.header
local set_header    = ngx.req.set_header
local read_body     = ngx.req.read_body
local get_uri_args  = ngx.req.get_uri_args
local get_body_data = ngx.req.get_body_data
local get_body_file = ngx.req.get_body_file
local get_post_args = ngx.req.get_post_args
local tonumber      = tonumber
local ipairs        = ipairs
local concat        = table.concat
local find          = string.find
local type          = type
local sub           = string.sub
local gsub          = string.gsub
local lower         = string.lower
local json          = codec.json
local base64        = codec.base64
local open          = io.open


local NOTICE        = ngx.NOTICE
local ERR           = ngx.ERR


local function read_file(p)
  local f, e = open(p, "rb")
  if not f then
    return nil, e
  end
  local c = f:read "*a"
  f:close()
  return c
end


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


local function multipart_value(r, s)
  if s == "formdata" then return end
  local e = find(s, "=", 1, true)
  if e then
    r[sub(s, 2, e - 1)] = sub(s, e + 2, #s - 1)
  else
    r[#r+1] = s
  end
end


local function multipart_parse(s)
  if not s then return nil end
  local r = {}
  local i = 1
  local b = find(s, ";", 1, true)
  while b do
    local p = sub(s, i, b - 1)
    multipart_value(r, p)
    i = b + 1
    b = find(s, ";", i, true)
  end
  local p = sub(s, i)
  if p ~= "" then multipart_value(r, p) end
  return r
end


local function multipart(name, timeout)
  local form = upload:new()
  if not form then return nil end
  local h, p
  form:set_timeout(timeout)
  while true do
    local t, r = form:read()
    if not t then return nil end
    if t == "header" then
      if not h then h = {} end
      if type(r) == "table" then
        local k, v = r[1], multipart_parse(r[2])
        if v then h[k] = v end
      end
    elseif t == "body" then
      if h then
        local d = h["Content-Disposition"]
        if d and d.name == name then
          p = { n = 1 }
        end
        h = nil
      end
      if p then
        local n = p.n
        p[n] = r
        p.n  = n + 1
      end
    elseif t == "part_end" then
      if p then
        p = concat(p)
        break
      end
    elseif t == "eof" then
      break
    end
  end
  local t = form:read()
  if not t then return nil end
  return p
end

local function consumer(conf, token, claim, anonymous)
  if not token then
    return nil, "token for consumer mapping was not found"
  end

  if type(token) ~= "table" then
    return nil, "opaque token cannot be used for consumer mapping"
  end

  local payload = token.payload

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

  return cache.consumers.load(conf, subject, anonymous)
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


local function unexpected(err)
  if err then
    log(ERR, err)
  end
  return responses.send_HTTP_INTERNAL_SERVER_ERROR()
end


local OICHandler = BasePlugin:extend()


function OICHandler:new()
  OICHandler.super.new(self, "openid-connect-authentication")
end


function OICHandler:init_worker()
  OICHandler.super.init_worker(self)
end


function OICHandler:access(conf)
  OICHandler.super.access(self)

  local issuer, err = cache.issuers.load(conf)
  if not issuer then
    return unexpected(err)
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
    return unexpected(err)
  end

  local iss = o.configuration.issuer

  local args, bearer

  local s, session_present = session.open()

  if not session_present then
    bearer = o.authorization:bearer()
    if bearer then
      -- Bearer Token
      s.data = {
        tokens = {
          access_token = bearer
        }
      }

      local id_token
      local content_type = var.content_type  or ""

      local id_token_param_name = conf.id_token_param_name
      if id_token_param_name then
        local id_token_param_type = conf.id_token_param_type or { "query", "header", "body" }

        for _, t in ipairs(id_token_param_type) do
          if t == "header" then
            local name = gsub(lower(id_token_param_name), "-", "_")
            id_token = var["http_" .. name]
            if id_token then
              break
            end
            id_token = var["http_x_" .. name]
            if id_token then
              break
            end

          elseif t == "query" then
            local uri_args = get_uri_args()
            if uri_args then
              id_token = uri_args[id_token_param_name]
              if id_token then
                break
              end
            end

          elseif t == "body" then
            if sub(content_type, 1, 33) == "application/x-www-form-urlencoded" then
              read_body()
              local post_args = get_post_args()
              if post_args then
                id_token = post_args[id_token_param_name]
                if id_token then
                  break
                end
              end

            elseif sub(content_type, 1, 19) == "multipart/form-data" then
              id_token = multipart(id_token_param_name, conf.timeout)
              if id_token then
                break
              end

            elseif sub(content_type, 1, 16) == "application/json" then
              read_body()
              local data = get_body_data()
              if data == nil then
                local file = get_body_file()
                if file ~= nil then
                  data = read_file(file)
                end
              end
              if data then
                local json_body = json.decode(data)
                if json_body then
                  id_token = json_body[id_token_param_name]
                  if id_token then
                    break
                  end
                end
              end

            else
              read_body()
              local data = get_body_data()
              if data == nil then
                local file = get_body_file()
                if file ~= nil then
                  id_token = read_file(file)
                  if id_token then
                    break
                  end
                end
              end
            end
          end
        end

        if id_token then
          s.data.tokens.id_token = id_token
        end
      end

    else
      -- Resource Owner Password and Client Credentials
      local identity, secret = o.authorization:basic()
      if identity and secret then
        args = {
          {
            username      = identity,
            password      = secret,
            grant_type    = "password",
          },
          {
            client_id     = identity,
            client_secret = secret,
            grant_type    = "client_credentials",
          },
        }

      else
        -- Authorization Code Request
        args, err = o.authorization:request()
        if not args then
          return unexpected(err)
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
  end

  local data = s.data or {}

  local state = data.state
  if state then
    -- Authorization Code Response
    args = {
      state         = state,
      nonce         = data.nonce,
      code_verifier = data.code_verifier,
    }

    args, err = o.authorization:verify(args)
    if not args then
      local uri_args = get_uri_args()
      if uri_args.state == state then
        return unauthorized(iss, err, s)
      end

      return unauthorized(iss, err)
   end

    args = { args }
  end

  local now = time()
  local expires
  local tokens_encoded, tokens_decoded, access_token_introspected = data.tokens, nil, nil

  if bearer then
    tokens_decoded, err = o.token:verify(tokens_encoded)
    if not tokens_decoded then
      return unauthorized(iss, err, s)
    end

    local access_token = tokens_decoded.access_token
    if type(access_token) ~= "table" then
      access_token_introspected, err = o.token:introspect(access_token, "access_token", {
          introspection_endpoint = conf.introspection_endpoint
      })
      if not access_token_introspected or not access_token_introspected.active then
        return unauthorized(iss, err, s)
      end

      expires = access_token_introspected.exp or (3600 + now)

    else
      expires = access_token.exp or (3600 + now)
    end

    s.data.expires = expires
    s:save()

  elseif not tokens_encoded then
    for _, arg in ipairs(args) do
      tokens_encoded, err = o.token:request(arg)
      if tokens_encoded then
        args = arg
        break
      end
    end

    if not tokens_encoded then
      return unauthorized(iss, err, s)
    end

    tokens_decoded, err = o.token:verify(tokens_encoded, args)
    if not tokens_decoded then
      return unauthorized(iss, err, s)
    end

    expires = (tonumber(tokens_encoded.expires_in) or 3600) + now

    s.data = {
      tokens  = tokens_encoded,
      expires = expires,
    }

    if session_present then
      s:regenerate()
    else
      s:save()
    end

    if state then
      local login_redirect_uri = conf.login_redirect_uri
      if login_redirect_uri then
        return redirect(login_redirect_uri .. "#id_token=" .. tokens_encoded.id_token)
      end
    end

  else
    expires = (data.expires or conf.leeway) - conf.leeway
  end

  if not tokens_encoded.access_token then
    return unauthorized(iss, "access token was not found", s)
  end

  if expires > now then
    s:start()
    if conf.reverify then
      tokens_decoded, err = o.token:verify(tokens_encoded)
      if not tokens_decoded then
        return unauthorized(iss, err)
      end
    end

  else
    -- Refresh Tokens

    if not tokens_encoded.refresh_token then
      return unauthorized(iss, "access token cannot be refreshed in absense of refresh token", s)
    end

    local tokens_refreshed
    local refresh_token = tokens_encoded.refresh_token
    tokens_refreshed, err = o.token:refresh(refresh_token)

    if not tokens_refreshed then
      return unauthorized(iss, err, s)
    end

    if not tokens_refreshed.id_token then
      tokens_refreshed.id_token = tokens_encoded.id_token
    end

    if not tokens_refreshed.refresh_token then
      tokens_refreshed.refresh_token = refresh_token
    end

    tokens_decoded, err = o.token:verify(tokens_refreshed)
    if not tokens_decoded then
      return unauthorized(iss, err, s)
    end

    tokens_encoded = tokens_refreshed

    expires = (tonumber(tokens_encoded.expires_in) or 3600) + now

    s.data = {
      tokens  = tokens_encoded,
      expires = expires,
    }

    s:regenerate()
  end

  local consumer_claim = conf.consumer_claim
  if consumer_claim and consumer_claim ~= "" then
    if not tokens_decoded then
      tokens_decoded, err = o.token:decode(tokens_encoded)
    end

    local mapped_consumer

    if tokens_decoded then
      local id_token = tokens_decoded.id_token
      if id_token then
        mapped_consumer, err = consumer(conf, id_token, consumer_claim)
        if not mapped_consumer then
          mapped_consumer = consumer(conf, tokens_decoded.access_token, consumer_claim)
        end

      else
        mapped_consumer, err = consumer(conf, tokens_decoded.access_token, consumer_claim)
      end
    end

    if not mapped_consumer and access_token_introspected then
      mapped_consumer, err = consumer(conf, access_token_introspected, consumer_claim)
    end

    local is_anonymous = false

    if not mapped_consumer then
      local anonymous = conf.anonymous
      if anonymous == nil or anonymous == "" then
        if err then
          return unauthorized(iss, "consumer was not found (" .. err .. ")", s)

        else
          return unauthorized(iss, "consumer was not found", s)
        end
      end

      is_anonymous = true

      local consumer_token = {
        payload = {
          [consumer_claim] = anonymous
        }
      }

      mapped_consumer, err = consumer(conf, consumer_token, consumer_claim, true)
      if not mapped_consumer then
        if err then
          return unauthorized(iss, "anonymous consumer was not found (" .. err .. ")", s)

        else
          return unauthorized(iss, "anonymous consumer was not found", s)
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

  set_header("Authorization", "Bearer " .. tokens_encoded.access_token)

  local access_token_jwk_header = conf.access_token_jwk_header
  if access_token_jwk_header and access_token_jwk_header ~= "" then
    if not tokens_decoded then
      tokens_decoded = o.token:decode(tokens_encoded)
    end
    if tokens_decoded then
      local access_token = tokens_decoded.access_token
      if access_token and access_token.jwk then
        local jwk = json.encode(access_token.jwk)
        if jwk then
          jwk = base64.encode(jwk)
          if jwk then
            set_header(access_token_jwk_header, jwk)
          end
        end
      end
    end
  end

  local id_token_header = conf.id_token_header
  if id_token_header and id_token_header ~= "" then
    local id_token = tokens_encoded.id_token
    if id_token then
      set_header(id_token_header, id_token)
    end
  end

  local id_token_jwk_header = conf.id_token_jwk_header
  if id_token_jwk_header and id_token_jwk_header ~= "" then
    if not tokens_decoded then
      tokens_decoded = o.token:decode(tokens_encoded)
    end
    if tokens_decoded then
      local id_token = tokens_decoded.id_token
      if id_token and id_token.jwk then
        local jwk = json.encode(id_token.jwk)
        if jwk then
          jwk = base64.encode(jwk)
          if jwk then
            set_header(id_token_jwk_header, jwk)
          end
        end
      end
    end
  end

  local userinfo_header = conf.userinfo_header
  if userinfo_header and userinfo_header ~= "" then
    local userinfo = o:userinfo(tokens_encoded.access_token, { userinfo_format = "base64" })
    if userinfo then
      set_header(userinfo_header, userinfo)
    end
  end

  local introspection_header = conf.intropection_header
  if introspection_header and access_token_introspected then
    local introspected = json.encode(access_token_introspected)
    if introspected then
      introspected = base64.encode(introspected)
      if introspected then
        set_header(introspection_header, introspected)
      end
    end
  end

end


OICHandler.PRIORITY = 1000


return OICHandler
