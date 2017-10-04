local BasePlugin   = require "kong.plugins.base_plugin"
local cache        = require "kong.plugins.openid-connect.cache"
local constants    = require "kong.constants"
local responses    = require "kong.tools.responses"
local oic          = require "kong.openid-connect"
local uri          = require "kong.openid-connect.uri"
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
local set_uri_args  = ngx.req.set_uri_args
local get_body_data = ngx.req.get_body_data
local get_body_file = ngx.req.get_body_file
local get_post_args = ngx.req.get_post_args
local get_headers   = ngx.req.get_headers
local tonumber      = tonumber
local tostring      = tostring
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


local function redirect_uri()
  -- we try to use current url as a redirect_uri by default
  -- if none is configured.

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


local function consumer(issuer, token, claim, anonymous, consumer_by)
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

  return cache.consumers.load(issuer, subject, anonymous, consumer_by)
end


local function client(param, clients, secrets, redirects)
  if param then
    local client_id, client_secret, client_redirect_uri
    local client_index = tonumber(param)
    if client_index then
      if clients[client_index] then
        client_id = clients[client_index]
        if client_id then
          client_id           =   clients[client_index]
          client_secret       =   secrets[client_index]
          client_redirect_uri = redirects[client_index] or redirects[1]
        end
      end
    else
      for i, c in ipairs(clients) do
        if param == c then
          client_id           =   clients[i]
          client_secret       =   secrets[i]
          client_redirect_uri = redirects[i] or redirects[1]
          break
        end
      end
    end
    return client_id, client_secret, client_redirect_uri
  end
end


local function append_header(name, value)
  if type(value) == "table" then
    for _, val in ipairs(value) do
      append_header(name, val)
    end

  else
    local header_value = header[name]

    if header_value ~= nil then
      if type(header_value) == "table" then
        header_value[#header_value+1] = value
      else
        header_value = { header_value, value }
      end

    else
      header_value = value
    end

    header[name] = header_value
  end
end


local function headers(upstream_header, downstream_header, header_value)
  local val = header_value ~= nil and header_value ~= "" and header_value ~= ngx.null and header_value
  if val then
    local usm =   upstream_header ~= nil      and
                  upstream_header ~= ""       and
                  upstream_header ~= ngx.null and
                  upstream_header
    local dsm = downstream_header ~= nil      and
                downstream_header ~= ""       and
                downstream_header ~= ngx.null and
                downstream_header

    if usm or dsm then
      local val_type = type(val)
      if val_type == "table" then
        val = json.encode(val)
        if val then
          val = base64.encode(val)
        end

      elseif val_type == "function" then
        return headers(usm, dsm, val())

      elseif val_type ~= "string" then
        val = tostring(val)
      end

      if not val then
        return
      end
    end

    if usm then
      if usm == "authorization:bearer" then
        set_header("Authorization", "Bearer " .. val)

      else
        set_header(usm, val)
      end
    end

    if dsm then
      if dsm == "authorization:bearer" then
        append_header("Authorization", "Bearer " .. val)

      else
        append_header(dsm, val)
      end
    end
  end
end


local function get_conf_args(args_names, args_values)
  if not args_names  or args_names  == "" or
     not args_values or args_values == "" then
    return nil
  end

  local args
  for i, name in ipairs(args_names) do
    if name and name ~= "" then
      if not args then
        args = {}
      end

      args[name] = args_values[i]
    end
  end
  return args
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


local function success(response)
  return responses.send_HTTP_OK(response)
end


local OICHandler = BasePlugin:extend()


function OICHandler:new()
  OICHandler.super.new(self, "openid-connect")
end


function OICHandler:init_worker()
  OICHandler.super.init_worker(self)
end


function OICHandler:access(conf)
  OICHandler.super.access(self)

  if ngx.ctx.authenticated_credential and conf.anonymous ~= ngx.null and conf.anonymous ~= "" then
    -- we're already authenticated, and we're configured for using anonymous,
    -- hence we're in a logical OR between auth methods and we're already done.
    return
  end

  -- load issuer configuration
  local issuer, err = cache.issuers.load(conf)
  if not issuer then
    return unexpected(err)
  end

  local clients   = conf.client_id
  local secrets   = conf.client_secret
  local redirects = conf.redirect_uri or {}

  local client_id, client_secret, client_redirect_uri

  -- try to find the right client
  if #clients > 1 then
    client_id, client_secret, client_redirect_uri = client(var.http_x_client_id, clients, secrets, redirects)
    if not client_id then
      client_id, client_secret, client_redirect_uri = client(var.http_client_id, clients, secrets, redirects)
      if not client_id then
        local uri_args = get_uri_args()
        client_id, client_secret, client_redirect_uri = client(uri_args.client_id, clients, secrets, redirects)
        if not client_id then
          read_body()
          local post_args = get_post_args()
          client_id, client_secret, client_redirect_uri = client(post_args.client_id, clients, secrets, redirects)
        end
      end
    end
  end

  -- fallback to default client
  if not client_secret then
    client_id           =   clients[1]
    client_secret       =   secrets[1]
    client_redirect_uri = redirects[1]
  end

  local o

  o, err = oic.new({
    client_id         = client_id,
    client_secret     = client_secret,
    redirect_uri      = client_redirect_uri or redirect_uri(),
    scope             = conf.scopes       or { "openid" },
    response_mode     = conf.response_mode,
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

  -- determine the supported authentication methods
  local auth_method_password
  local auth_method_client_credentials
  local auth_method_authorization_code
  local auth_method_bearer
  local auth_method_introspection
  local auth_method_kong_oauth2
  local auth_method_refresh_token
  local auth_method_session

  local auth_methods = conf.auth_methods or {
    "password",
    "client_credentials",
    "authorization_code",
    "bearer",
    "introspection",
    "refresh_token",
    "session",
  }

  for _, auth_method in ipairs(auth_methods) do
    if auth_method == "password" then
      auth_method_password = true

    elseif auth_method == "client_credentials" then
      auth_method_client_credentials = true

    elseif auth_method == "authorization_code" then
      auth_method_authorization_code = true

    elseif auth_method == "bearer" then
      auth_method_bearer = true

    elseif auth_method == "introspection" then
      auth_method_introspection = true

    elseif auth_method == "kong_oauth2" then
      auth_method_kong_oauth2 = true

    elseif auth_method == "refresh_token" then
      auth_method_refresh_token = true

    elseif auth_method == "session" then
      auth_method_session = true
    end
  end

  local iss = o.configuration.issuer

  local args, bearer, state

  local s, session_present, session_data

  if auth_method_session then
    local session_cookie_name = conf.session_cookie_name
    if not session_cookie_name or session_cookie_name == "" then
      session_cookie_name = "authorization"
    end

    s, session_present = session.open {
      name = session_cookie_name,
      secret = issuer.secret
    }
    session_data = s.data
  end

  if not session_present then
    -- step 1: let's figure out the authentication method

    -- bearer token authentication
    if auth_method_bearer or auth_method_introspection then
      bearer = o.authorization:bearer()
      if bearer then
        session_data = {
          tokens = {
            access_token = bearer
          }
        }

        -- additionally we can validate the id token as well
        -- and pass it on, if it is passed on the request
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
            session_data.tokens.id_token = id_token
          end
        end
      end
    end

    if not bearer then
      -- resource owner password and client credentials grants
      if auth_method_password or auth_method_client_credentials then
        local identity, secret = o.authorization:basic()
        if identity and secret then
          args = {}
          if auth_method_password then
            args[1] = {
              username      = identity,
              password      = secret,
              grant_type    = "password",
            }
          end

          if auth_method_client_credentials then
            args[auth_method_password and 2 or 1] = {
              client_id     = identity,
              client_secret = secret,
              grant_type    = "client_credentials",
            }
          end
        end
      end

      if not args then
        -- authorization code grant
        if auth_method_authorization_code then
          local authorization_cookie_name = conf.authorization_cookie_name
          if not authorization_cookie_name or authorization_cookie_name == "" then
            authorization_cookie_name = "authorization"
          end

          local authorization, authorization_present = session.open {
            name   = authorization_cookie_name,
            secret = issuer.secret,
            cookie = {
              samesite = "off",
            }
          }

          if authorization_present then
            local authorization_data = authorization.data or {}

            state = authorization_data.state

            if state then
              local nonce         = authorization_data.nonce
              local code_verifier = authorization_data.code_verifier

              -- authorization code response
              args = {
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
                  args          = get_conf_args(conf.authorization_query_args_names,
                                                conf.authorization_query_args_values),
                  state         = state,
                  nonce         = nonce,
                  code_verifier = code_verifier,
                }

                if not args then
                  return unexpected(err)
                end

                return redirect(args.url)
              end

              authorization:hide()
              authorization:destroy()

              uri_args.code  = nil
              uri_args.state = nil

              set_uri_args(uri_args)

              args = { args }
            end
          end

          if not args then
            -- authorization code request
            args, err = o.authorization:request()
            if not args then
              return unexpected(err)
            end

            authorization.data = {
              args          = get_conf_args(conf.authorization_query_args_names,
                                            conf.authorization_query_args_values),
              state         = args.state,
              nonce         = args.nonce,
              code_verifier = args.code_verifier,
            }

            authorization:save()

            return redirect(args.url)
          end

        else
          return unauthorized(iss, "no suitable authorization credentials were provided")
        end
      end
    end
  end

  if not session_data then
    session_data = {}
  end

  local credential, mapped_consumer
  local default_expires_in = 3600
  local now = time()
  local exp = now + default_expires_in
  local expires
  local tokens_encoded, tokens_decoded, access_token_introspected = session_data.tokens, nil, nil
  local grant_type
  local extra_headers

  -- bearer token was present in a request, let's verify it
  if bearer then
    -- TODO: cache token verification(?)
    tokens_decoded, err = o.token:verify(tokens_encoded)
    if not tokens_decoded then
      return unauthorized(iss, err, s)
    end

    local access_token_decoded = tokens_decoded.access_token

    -- introspection of opaque access token
    if type(access_token_decoded) ~= "table" then

      if auth_method_kong_oauth2 then
        access_token_introspected, credential, mapped_consumer = cache.oauth2.load(access_token_decoded)
      end

      if not access_token_introspected then
        if auth_method_introspection then
          if conf.cache_introspection then
            -- TODO: we just cache this for default one hour, not sure if there should be another strategy
            -- TODO: actually the alternative is already proposed, but needs changes in core where ttl
            -- TODO: and neg_ttl can be set after the results are retrieved from identity provider
            -- TODO: see: https://github.com/thibaultcha/lua-resty-mlcache/pull/23
            access_token_introspected = cache.introspection.load(
              o,access_token_decoded, conf.introspection_endpoint, exp
            )
          else
            access_token_introspected = o.token:introspect(access_token_decoded, "access_token", {
              introspection_endpoint = conf.introspection_endpoint
            })
          end
        end

        if not access_token_introspected or not access_token_introspected.active then
          return unauthorized(iss, err, s)
        end
      end

      expires = access_token_introspected.exp or exp

    else
      -- additional non-standard verification of the claim against a jwt session cookie
      local jwt_session_cookie = conf.jwt_session_cookie
      if jwt_session_cookie and jwt_session_cookie ~= "" then
        local jwt_session_cookie_value = var["cookie_" .. jwt_session_cookie]
        if not jwt_session_cookie_value or jwt_session_cookie_value == "" then
          return unauthorized(iss, "jwt session cookie was not specified for session claim verification", s)
        end

        local jwt_session_claim = conf.jwt_session_claim or "sid"
        local jwt_session_claim_value = access_token_decoded.payload[jwt_session_claim]

        if not jwt_session_claim_value then
          return unauthorized(
            iss,"jwt session claim (" .. jwt_session_claim .. ") was not specified in jwt access token", s
          )
        end

        if jwt_session_claim_value ~= jwt_session_cookie_value then
          return unauthorized(
            iss, "invalid jwt session claim (" .. jwt_session_claim .. ") was specified in jwt access token", s
          )
        end
      end

      expires = access_token_decoded.exp or exp
    end

    if auth_method_session then
      s.data.expires = expires
      s:save()
    end

  elseif not tokens_encoded then
    -- let's try to retrieve tokens when using authorization code flow,
    -- password credentials or client credentials
    if args then
      for _, arg in ipairs(args) do
        arg.args = get_conf_args(
          conf.token_post_args_names,
          conf.token_post_args_values)

        local token_headers_client = conf.token_headers_client
        if token_headers_client and token_headers_client ~= "" then
          local req_headers = get_headers()
          local token_headers = {}
          local has_headers
          for _, name in ipairs(token_headers_client) do
            local req_header = req_headers[name]
            if req_header then
              token_headers[name] = req_header
              has_headers = true
            end
          end
          if has_headers then
            arg.headers = token_headers
          end
        end

        if conf.cache_tokens then
          -- TODO: we just cache this for default one hour, not sure if there should be another strategy
          -- TODO: actually the alternative is already proposed, but needs changes in core where ttl
          -- TODO: and neg_ttl can be set after the results are retrieved from identity provider
          -- TODO: see: https://github.com/thibaultcha/lua-resty-mlcache/pull/23
          tokens_encoded, err, extra_headers = cache.tokens.load(o, arg, exp)
        else
          tokens_encoded, err, extra_headers = o.token:request(arg)
        end

        if tokens_encoded then
          grant_type = arg.grant_type or "authorization_code"
          args = arg
          break
        end
      end
    end

    if not tokens_encoded then
      return unauthorized(iss, err, s)
    end

    -- TODO: cache token verification(?)
    tokens_decoded, err = o.token:verify(tokens_encoded, args)
    if not tokens_decoded then
      return unauthorized(iss, err, s)
    end

    expires = (tonumber(tokens_encoded.expires_in) or default_expires_in) + now

    if auth_method_session then
      s.data = {
        tokens  = tokens_encoded,
        expires = expires,
      }

      if session_present then
        s:regenerate()

      else
        s:save()
      end
    end

    if state then
      local login_action = conf.login_action
      if login_action == "response" then
        local response = {}
        local login_tokens = conf.login_tokens
        for _, name in ipairs(login_tokens) do
          if tokens_encoded[name] then
            response[name] = tokens_encoded[name]
          end
        end

        -- TODO: should we set downstream headers here as well?
        return success(response)

      elseif login_action == "redirect" and conf.login_redirect_uri then
        local login_redirect_uri, i = { conf.login_redirect_uri }, 2
        local login_tokens = conf.login_tokens
        for _, name in ipairs(login_tokens) do
          if tokens_encoded[name] then
            if i == 1 then
              login_redirect_uri[i] = "#"

            else
              login_redirect_uri[i] = "&"
            end

            login_redirect_uri[i+1] = name
            login_redirect_uri[i+2] = "="
            login_redirect_uri[i+3] = tokens_encoded[name]
            i = i + 4
          end
        end

        -- TODO: should we set downstream headers here as well?
        return redirect(concat(login_redirect_uri))
      end
    end

  else
    -- it looks like we are using session authentication
    expires = (session_data.expires or conf.leeway)
  end

  if not tokens_encoded.access_token then
    return unauthorized(iss, "access token was not found", s)
  end

  expires = (expires or conf.leeway) - conf.leeway

  if expires > now then
    if auth_method_session then
      s:start()
    end

    if conf.reverify then
      tokens_decoded, err = o.token:verify(tokens_encoded)
      if not tokens_decoded then
        return forbidden(iss, err)
      end
    end

  else
    if auth_method_refresh_token then
      -- access token has expired, try to refresh the access token before proxying
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

      if auth_method_session then
        s.data = {
          tokens  = tokens_encoded,
          expires = expires,
        }

        s:regenerate()
      end

    else
      return forbidden(iss, err, s)
    end
  end

  local is_anonymous

  if not mapped_consumer then
    local consumer_claim = conf.consumer_claim
    if consumer_claim and consumer_claim ~= "" then
      local consumer_by = conf.consumer_by

      if not tokens_decoded then
        tokens_decoded, err = o.token:decode(tokens_encoded)
      end

      if tokens_decoded then
        local id_token = tokens_decoded.id_token
        if id_token then
          mapped_consumer, err = consumer(iss, id_token, consumer_claim, false, consumer_by)
          if not mapped_consumer then
            mapped_consumer = consumer(iss, tokens_decoded.access_token, consumer_claim, false, consumer_by)
          end

        else
          mapped_consumer, err = consumer(iss, tokens_decoded.access_token, consumer_claim, false, consumer_by)
        end
      end

      if not mapped_consumer and access_token_introspected then
        mapped_consumer, err = consumer(iss, access_token_introspected, consumer_claim, false, consumer_by)
      end

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

        mapped_consumer, err = consumer(iss, consumer_token, consumer_claim, true, consumer_by)
        if not mapped_consumer then
          if err then
            return forbidden(iss, "anonymous consumer was not found (" .. err .. ")", s)

          else
            return forbidden(iss, "anonymous consumer was not found", s)
          end
        end
      end
    end
  end

  if mapped_consumer then
    local head = constants.HEADERS

    ngx.ctx.authenticated_consumer = mapped_consumer

    if credential then
      ngx.ctx.authenticated_credential = credential
    else
      ngx.ctx.authenticated_credential = {
        consumer_id = mapped_consumer.id
      }
    end

    set_header(head.CONSUMER_ID,        mapped_consumer.id)
    set_header(head.CONSUMER_CUSTOM_ID, mapped_consumer.custom_id)
    set_header(head.CONSUMER_USERNAME,  mapped_consumer.username)

    if is_anonymous then
      set_header(head.ANONYMOUS, is_anonymous)
    end
  end

  -- remove session cookie from the upstream request?
  if auth_method_session then
    s:hide()
  end

  -- TODO: do we want to set downstream headers for users that authenticated with session

  -- here we replay token endpoint request response headers, if any
  if extra_headers and grant_type then
    local replay_for = conf.token_headers_grants
    if replay_for ~= nil and
       replay_for ~= ""  and
       replay_for ~= ngx.null then

      local replay_prefix = conf.token_headers_prefix
      if replay_prefix == ""  or
         replay_prefix == ngx.null then
        replay_prefix = nil
      end

      for _, v in ipairs(replay_for) do
        if v == grant_type then
          local replay_headers = conf.token_headers_replay
          if replay_headers ~= nil and
             replay_headers ~= ""  and
             replay_headers ~= ngx.null then
            for _, replay_header in ipairs(replay_headers) do
              local extra_header = extra_headers[replay_header]
              if extra_header then
                if replay_prefix then
                  append_header(replay_prefix .. replay_header, extra_header)

                else
                  append_header(replay_header, extra_header)
                end
              end
            end
          end
          break
        end
      end
    end
  end

  -- now let's setup the upstream and downstream headers
  headers(
    conf.upstream_access_token_header,
    conf.downstream_access_token_header,
    tokens_encoded.access_token
  )

  headers(
    conf.upstream_id_token_header,
    conf.downstream_id_token_header,
    tokens_encoded.id_token
  )

  headers(
    conf.upstream_refresh_token_header,
    conf.downstream_refresh_token_header,
    tokens_encoded.refresh_token
  )

  headers(
    conf.upstream_introspection_header,
    conf.downstream_introspection_header,
    access_token_introspected
  )

  headers(
    conf.upstream_user_info_header,
    conf.downstream_user_info_header,
    function()
      if conf.cache_user_info then
        return cache.userinfo.load(o, tokens_encoded.access_token, expires - now)
      else
        return o:userinfo(tokens_encoded.access_token, { userinfo_format = "base64" })
      end
    end
  )

  headers(
    conf.upstream_access_token_jwk_header,
    conf.downstream_access_token_jwk_header,
    function()
      if not tokens_decoded then
        -- TODO: cache token decoded(?)
        tokens_decoded = o.token:decode(tokens_encoded)
      end
      if tokens_decoded then
        local access_token = tokens_decoded.access_token
        if access_token and access_token.jwk then
          return access_token.jwk
        end
      end
    end
  )

  headers(
    conf.upstream_id_token_jwk_header,
    conf.downstream_id_token_jwk_header,
    function()
      if not tokens_decoded then
        -- TODO: cache token decoded(?)
        tokens_decoded = o.token:decode(tokens_encoded)
      end
      if tokens_decoded then
        local id_token = tokens_decoded.id_token
        if id_token and id_token.jwk then
          return id_token.jwk
        end
      end
    end
  )
end


if cache.is_0_10 then
  OICHandler.PRIORITY = 1000
else
  OICHandler.PRIORITY = 1790
end


return OICHandler
