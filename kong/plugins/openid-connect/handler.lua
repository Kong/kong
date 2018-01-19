local BasePlugin    = require "kong.plugins.base_plugin"
local cache         = require "kong.plugins.openid-connect.cache"
local constants     = require "kong.constants"
local responses     = require "kong.tools.responses"
local oic           = require "kong.openid-connect"
local uri           = require "kong.openid-connect.uri"
local codec         = require "kong.openid-connect.codec"
local session       = require "resty.session"
local upload        = require "resty.upload"


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
local escape_uri    = ngx.escape_uri
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


local DEBUG         = ngx.DEBUG
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
  if type(scheme) == "table" then
    scheme = scheme[1]
  end

  local host = var.host
  if type(host) == "table" then
    host = host[1]
  end

  local port = var.server_port
  if type(port) == "table" then
    port = port[1]
  end

  port = tonumber(port)

  local u = var.request_uri
  if type(u) == "table" then
    u = u[1]
  end

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
  if s == "form-data" then
    return
  end

  local e = find(s, "=", 1, true)
  if e then
    r[sub(s, 2, e - 1)] = sub(s, e + 2, #s - 1)

  else
    r[#r + 1] = s
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
  if p ~= "" then
    multipart_value(r, p)
  end

  return r
end


local function multipart(name, timeout)
  local form = upload:new()
  if not form then
    return nil
  end

  form:set_timeout(timeout)

  local h, p

  while true do
    local t, r = form:read()
    if not t then
      return nil
    end

    if t == "header" then
      if not h then
        h = {}
      end

      if type(r) == "table" then
        local k, v = r[1], multipart_parse(r[2])
        if v then
          h[k] = v
        end
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

  return p
end


local function consumer(token, claim, anonymous, consumer_by)
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

  return cache.consumers.load(subject, anonymous, consumer_by)
end


local function client(param, clients)
  if not param then
    return nil
  end

  if type(param) == "table" then
    param = param[1]
  end

  local client_index = tonumber(param)
  if client_index then
    if clients[client_index] then
      local client_id = clients[client_index]
      if client_id then
        return client_id, client_index
      end
    end

    return
  end

  for i, c in ipairs(clients) do
    if param == c then
      return clients[i], i
    end
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


local function get_conf_arg(conf, name, default)
  local value = conf[name]
  if value ~= nil and value ~= ngx.null and value ~= "" then
    return value
  end

  return default
end


local function unexpected(err)
  if err then
    log(ERR, err)
  end

  return responses.send_HTTP_INTERNAL_SERVER_ERROR()
end


local function anonymous_access(issuer, anonymous)
  local consumer_token = {
    payload = {
      id = anonymous
    }
  }

  local consumer, err = consumer(consumer_token, "id", true, "id")
  if not consumer then
    if err then
      return unexpected("[openid-connect] anonymous consumer was not found (" .. err .. ")")

    else
      return unexpected("[openid-connect] anonymous consumer was not found")
    end
  end

  local head = constants.HEADERS

  ngx.ctx.authenticated_consumer   = consumer
  ngx.ctx.authenticated_credential = nil

  set_header(head.CONSUMER_ID,        consumer.id)
  set_header(head.CONSUMER_CUSTOM_ID, consumer.custom_id)
  set_header(head.CONSUMER_USERNAME,  consumer.username)
  set_header(head.ANONYMOUS,          true)
end


local function unauthorized(issuer, err, s, anonymous)
  if err then
    log(NOTICE, err)
  end

  if s then
    s:destroy()
  end

  if anonymous then
    return anonymous_access(issuer, anonymous)
  end

  local parts = uri.parse(issuer)
  header["WWW-Authenticate"] = 'Bearer realm="' .. parts.host .. '"'
  return responses.send_HTTP_UNAUTHORIZED()
end


local function forbidden(issuer, err, s, anonymous)
  if err then
    log(NOTICE, err)
  end

  if s then
    s:destroy()
  end

  if anonymous then
    return anonymous_access(issuer, anonymous)
  end

  local parts = uri.parse(issuer)
  header["WWW-Authenticate"] = 'Bearer realm="' .. parts.host .. '"'
  return responses.send_HTTP_FORBIDDEN()
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
  cache.init_worker()
end


function OICHandler:access(conf)
  OICHandler.super.access(self)

  local anonymous = get_conf_arg(conf, "anonymous")

  if ngx.ctx.authenticated_credential and anonymous then
    -- we're already authenticated, and we're configured for using anonymous,
    -- hence we're in a logical OR between auth methods and we're already done.
    log(DEBUG, "[openid-connect] skipping because user is already authenticated")
    return
  end

  -- load issuer configuration
  log(DEBUG, "[openid-connect] loading discovery information")
  local issuer, err = cache.issuers.load(conf)
  if not issuer then
    return unexpected(err)
  end

  local clients   = get_conf_arg(conf, "client_id",     {})
  local secrets   = get_conf_arg(conf, "client_secret", {})
  local redirects = get_conf_arg(conf, "redirect_uri",  {})

  local  login_redirect_uris = get_conf_arg(conf,  "login_redirect_uri",  {})
  local logout_redirect_uris = get_conf_arg(conf, "logout_redirect_uri",  {})

  local client_id, client_secret, client_redirect_uri, client_index
  local login_redirect_uri, logout_redirect_uri
  local uri_args, post_args

  if #clients > 1 then
    local client_arg = get_conf_arg(conf,  "client_arg",  "client_id")

    client_id, client_index = client(var["http_x_" .. client_arg], clients)

    if not client_id then
      client_id, client_index = client(var["http_" .. client_arg], clients)

      if not client_id then
        uri_args = get_uri_args()
        client_id, client_index = client(uri_args[client_arg], clients)

        if not client_id then
          read_body()
          post_args = get_post_args()
          client_id, client_index = client(post_args[client_arg], clients)
        end
      end
    end
  end

  if client_id then
    client_secret       =              secrets[client_index] or              secrets[1]
    client_redirect_uri =            redirects[client_index] or            redirects[1] or redirect_uri()
    login_redirect_uri  =  login_redirect_uris[client_index] or  login_redirect_uris[1]
    logout_redirect_uri = logout_redirect_uris[client_index] or logout_redirect_uris[1]

  else
    client_id           =              clients[1]
    client_secret       =              secrets[1]
    client_redirect_uri =            redirects[1] or redirect_uri()
    login_redirect_uri  =  login_redirect_uris[1]
    logout_redirect_uri = logout_redirect_uris[1]

    client_index        = 1
  end

  local options = {
    client_id         = client_id,
    client_secret     = client_secret,
    redirect_uri      = client_redirect_uri,
    scope             = get_conf_arg(conf, "scopes", { "openid" }),
    response_mode     = get_conf_arg(conf, "response_mode"),
    audience          = get_conf_arg(conf, "audience"),
    domains           = get_conf_arg(conf, "domains"),
    max_age           = get_conf_arg(conf, "max_age"),
    timeout           = get_conf_arg(conf, "timeout", 10000),
    leeway            = get_conf_arg(conf, "leeway", 0),
    http_version      = get_conf_arg(conf, "http_version", 1.1),
    ssl_verify        = get_conf_arg(conf, "ssl_verify", true),
    verify_parameters = get_conf_arg(conf, "verify_parameters"),
    verify_nonce      = get_conf_arg(conf, "verify_nonce"),
    verify_signature  = get_conf_arg(conf, "verify_signature"),
    verify_claims     = get_conf_arg(conf, "verify_claims"),
  }

  local o

  log(DEBUG, "[openid-connect] initializing library")
  o, err = oic.new(options, issuer.configuration, issuer.keys)

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

  local auth_methods = get_conf_arg(conf, "auth_methods", {
    "password",
    "client_credentials",
    "authorization_code",
    "bearer",
    "introspection",
    "refresh_token",
    "session",
  })

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

  local args, bearer, state

  local s, session_present, session_data

  if auth_method_session then
    local session_cookie_name = get_conf_arg(conf, "session_cookie_name",  "session")

    log(DEBUG, "[openid-connect] trying to open session")

    s, session_present = session.open {
      name   = session_cookie_name,
      secret = issuer.secret
    }

    session_data = s.data
  end

  local iss = o.configuration.issuer

  do
    local logout = false
    local logout_methods = get_conf_arg(conf, "logout_methods", { "POST", "DELETE" })

    if logout_methods then
      local request_method = var.request_method
      if type(request_method) == "table" then
        request_method = request_method[1]
      end

      for _, m in ipairs(logout_methods) do
        if m == request_method then
          logout = true
          break
        end
      end

      if logout then
        logout = false

        local logout_query_arg = get_conf_arg(conf, "logout_query_arg")

        if logout_query_arg then
          if not uri_args then
            uri_args = get_uri_args()
          end

           logout = uri_args[logout_query_arg] ~= nil
        end

        if logout then
          log(DEBUG, "[openid-connect] logout by query argument")

        else
          local logout_uri_suffix = get_conf_arg(conf, "logout_uri_suffix")
          if logout_uri_suffix then
            local ruri = var.request_uri
            if type(ruri) == "table" then
              ruri = ruri[1]
            end

            logout = sub(ruri, -#logout_uri_suffix) == logout_uri_suffix

            if logout then
              log(DEBUG, "[openid-connect] logout by uri suffix")

            else
              local logout_post_arg = get_conf_arg(conf, "logout_post_arg")

              if logout_post_arg then
                if not post_args then
                  read_body()
                  post_args = get_post_args()
                end

                if post_args then
                  logout = post_args[logout_post_arg] ~= nil

                  if logout then
                    log(DEBUG, "[openid-connect] logout by post argument")
                  end
                end
              end
            end
          end
        end
      end

      if logout then
        local id_token

        if session_present and session_data then

          local new_client_index = session_data.client or client_index
          if new_client_index ~= client_index and #clients > 1 then
            local new_client_id

            new_client_id, new_client_index = client(new_client_index, clients)
            if new_client_id then
              client_id             = new_client_id

              client_secret         =              secrets[new_client_index] or client_secret
              client_redirect_uri   =            redirects[new_client_index] or client_redirect_uri
              logout_redirect_uri   = logout_redirect_uris[new_client_index] or logout_redirect_uri

              options.client_id     = client_id
              options.client_secret = client_secret
              options.redirect_uri  = client_redirect_uri

              o.options:reset(options)
            end
          end

          if session_data.tokens then
            id_token = session_data.tokens.id_token

            if session_data.tokens.access_token then
              if get_conf_arg(conf, "logout_revoke", false) then
                log(DEBUG, "[openid-connect] revoking access token")
                local ok
                ok, err = o.token:revoke(session_data.tokens.access_token, "access_token", {
                  revocation_endpoint = get_conf_arg(conf, "revocation_endpoint")
                })
                if not ok and err then
                  log(DEBUG, "[openid-connect] revoking access token failed: " .. err)
                end
              end
            end
          end

          log(DEBUG, "[openid-connect] destroying session")
          s:destroy()
        end

        header["Cache-Control"] = "no-cache, no-store"
        header["Pragma"]        = "no-cache"

        local end_session_endpoint = get_conf_arg(conf, "end_session_endpoint", o.configuration.end_session_endpoint)

        if end_session_endpoint then
          local redirect_params_added = false

          if find(end_session_endpoint, "?", 1, true) then
            redirect_params_added = true
          end

          local ruri = { end_session_endpoint }
          local ridx = 1

          if id_token then
            ruri[ridx + 1] = redirect_params_added and "&id_token_hint=" or "?id_token_hint="
            ruri[ridx + 2] = id_token
            ridx = ridx + 2
            redirect_params_added = true
          end

          if logout_redirect_uri then
            ruri[ridx + 1] = redirect_params_added and "&post_logout_redirect_uri=" or "?post_logout_redirect_uri="
            ruri[ridx + 2] = escape_uri(logout_redirect_uri)
          end

          log(DEBUG, "[openid-connect] redirecting to end session endpoint")
          return redirect(concat(ruri))

        else
          if logout_redirect_uri then
            log(DEBUG, "[openid-connect] redirecting to logout redirect uri")
            return redirect(logout_redirect_uri)
          end

          log(DEBUG, "[openid-connect] logout response")
          return responses.send_HTTP_OK()
        end
      end
    end
  end

  if not session_present then
    log(DEBUG, "[openid-connect] session was not found")

    -- bearer token authentication
    if auth_method_bearer or auth_method_introspection then
      log(DEBUG, "[openid-connect] trying to find bearer token")
      bearer = o.authorization:bearer()
      if bearer then
        log(DEBUG, "[openid-connect] found bearer token")

        session_data = {
          client = client_index,
          tokens = {
            access_token = bearer
          }
        }

        -- additionally we can validate the id token as well
        -- and pass it on, if it is passed on the request
        local id_token
        local content_type = var.content_type  or ""

        if type(content_type) == "table" then
          content_type = content_type[1] or ""
        end

        local id_token_param_name = get_conf_arg(conf, "id_token_param_name")
        if id_token_param_name then
          log(DEBUG, "[openid-connect] trying to find id token")

          local id_token_param_type = get_conf_arg(conf, "id_token_param_type", { "query", "header", "body" })

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
              if not uri_args then
                uri_args = get_uri_args()
              end
              if uri_args then
                id_token = uri_args[id_token_param_name]
                if id_token then
                  break
                end
              end

            elseif t == "body" then
              if sub(content_type, 1, 33) == "application/x-www-form-urlencoded" then
                if not post_args then
                  read_body()
                  post_args = get_post_args()
                end
                if post_args then
                  id_token = post_args[id_token_param_name]
                  if id_token then
                    break
                  end
                end

              elseif sub(content_type, 1, 19) == "multipart/form-data" then
                id_token = multipart(id_token_param_name, get_conf_arg(conf, "timeout"))
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
            log(DEBUG, "[openid-connect] found id token")
            session_data.tokens.id_token = id_token

          else
            log(DEBUG, "[openid-connect] id token was not found")
          end
        end

      else
        log(DEBUG, "[openid-connect] bearer token was not found")
      end
    end

    if not bearer then
      -- resource owner password and client credentials grants
      if auth_method_password or auth_method_client_credentials then
        log(DEBUG, "[openid-connect] trying to find basic authentication")

        local identity, secret, grant_type = o.authorization:basic()
        if identity and secret then
          log(DEBUG, "[openid-connect] found basic authentication")

          args = {}

          local arg_c = 0

          if grant_type ~= "client_credentials" then
            if auth_method_password then
              arg_c = arg_c + 1

              args[arg_c] = {
                username      = identity,
                password      = secret,
                grant_type    = "password",
              }
            end
          end

          if grant_type ~= "password" then
            if auth_method_client_credentials then
              arg_c = arg_c + 1

              args[arg_c] = {
                client_id     = identity,
                client_secret = secret,
                grant_type    = "client_credentials",
              }
            end
          end

        else
          log(DEBUG, "[openid-connect] basic authentication was not found")
        end
      end

      if not args then
        -- authorization code grant
        if auth_method_authorization_code then
          log(DEBUG, "[openid-connect] trying to open authorization code flow session")

          local authorization_cookie_name = get_conf_arg(conf, "authorization_cookie_name", "authorization")

          local authorization, authorization_present = session.open {
            name   = authorization_cookie_name,
            secret = issuer.secret,
            cookie = {
              samesite = "off",
            }
          }

          if authorization_present then
            log(DEBUG, "[openid-connect] found authorization code flow session")

            local authorization_data = authorization.data or {}

            log(DEBUG, "[openid-connect] checking authorization code flow state")

            state = authorization_data.state

            if state then
              log(DEBUG, "[openid-connect] found authorization code flow state")

              local nonce         = authorization_data.nonce
              local code_verifier = authorization_data.code_verifier

              local new_client_index = authorization_data.client or client_index
              if new_client_index ~= client_index and #clients > 1 then
                local new_client_id

                new_client_id, new_client_index = client(new_client_index, clients)
                if new_client_id then
                  client_id             = new_client_id
                  client_index          = new_client_index

                  client_secret         =             secrets[new_client_index] or client_secret
                  client_redirect_uri   =           redirects[new_client_index] or client_redirect_uri
                   login_redirect_uri   = login_redirect_uris[new_client_index] or  login_redirect_uri

                  options.client_id     = client_id
                  options.client_secret = client_secret
                  options.redirect_uri  = client_redirect_uri

                  o.options:reset(options)
                end
              end

              -- authorization code response
              args = {
                state         = state,
                nonce         = nonce,
                code_verifier = code_verifier,
              }

              if not uri_args then
                uri_args = get_uri_args()
              end

              log(DEBUG, "[openid-connect] verifying authorization code flow")

              args, err = o.authorization:verify(args)
              if not args then
                log(DEBUG, "[openid-connect] invalid authorization code flow")

                header["Cache-Control"] = "no-cache, no-store"
                header["Pragma"]        = "no-cache"

                if uri_args.state == state then
                  return unauthorized(iss, err, authorization, anonymous)

                else
                  if not post_args then
                    read_body()
                    post_args = get_post_args()
                  end
                  if post_args.state == state then
                    return unauthorized(iss, err, authorization, anonymous)
                  end
                end

                log(DEBUG, "[openid-connect] starting a new authorization code flow with previous parameters")
                -- it seems that user may have opened a second tab
                -- lets redirect that to idp as well in case user
                -- had closed the previous, but with same parameters
                -- as before.
                authorization:start()

                log(DEBUG, "[openid-connect] creating authorization code flow request with previous parameters")
                args, err = o.authorization:request {
                  args          = authorization_data.args,
                  client        = client_index,
                  state         = state,
                  nonce         = nonce,
                  code_verifier = code_verifier,
                }

                if not args then
                  log(DEBUG,
                    "[openid-connect] unable to start authorization code flow request with previous parameters")
                  return unexpected(err)
                end

                log(DEBUG, "[openid-connect] redirecting client to openid connect provider with previous parameters")
                return redirect(args.url)
              end

              log(DEBUG, "[openid-connect] authorization code flow verified")

              authorization:hide()
              authorization:destroy()

              uri_args.code  = nil
              uri_args.state = nil

              set_uri_args(uri_args)

              args = { args }
            end

          else
            log(DEBUG, "[openid-connect] authorization code flow session was not found")
          end

          if not args then
            log(DEBUG, "[openid-connect] creating authorization code flow request")
            -- authorization code request

            header["Cache-Control"] = "no-cache, no-store"
            header["Pragma"]        = "no-cache"

            local extra_args = get_conf_args(conf.authorization_query_args_names,
                                             conf.authorization_query_args_values)

            local client_args = get_conf_arg(conf, "authorization_query_args_client")

            if client_args then
              for _, arg_name in ipairs(client_args) do
                if not uri_args then
                  uri_args = get_uri_args()
                end

                if uri_args[arg_name] then
                  if not extra_args then
                    extra_args = {}
                  end

                  extra_args[arg_name] = uri_args[arg_name]

                else
                  if not post_args then
                    read_body()
                    post_args = get_post_args()
                  end

                  if post_args[arg_name] then
                    if not extra_args then
                      extra_args = {}
                    end

                    extra_args[arg_name] = uri_args[arg_name]
                  end
                end
              end
            end

            args, err = o.authorization:request {
              args = extra_args,
            }

            if not args then
              log(DEBUG, "[openid-connect] unable to start authorization code flow request")
              return unexpected(err)
            end

            authorization.data = {
              args          = extra_args,
              client        = client_index,
              state         = args.state,
              nonce         = args.nonce,
              code_verifier = args.code_verifier,
            }

            authorization:save()

            log(DEBUG, "[openid-connect] redirecting client to openid connect provider")
            return redirect(args.url)

          else
            log(DEBUG, "[openid-connect] authenticating using authorization code flow")
          end

        else
          return unauthorized(iss, "no suitable authorization credentials were provided", nil, anonymous)
        end
      end

    else
      log(DEBUG, "[openid-connect] authenticating using bearer token")
    end

  else
    log(DEBUG, "[openid-connect] authenticating using session")
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
  local leeway = get_conf_arg(conf, "leeway", 0)

  -- bearer token was present in a request, let's verify it
  if bearer then
    log(DEBUG, "[openid-connect] verifying bearer token")

    -- TODO: cache token verification
    tokens_decoded, err = o.token:verify(tokens_encoded)
    if not tokens_decoded then
      log(DEBUG, "[openid-connect] unable to verify bearer token")
      return unauthorized(iss, err, s, anonymous)
    end

    log(DEBUG, "[openid-connect] bearer token verified")
    local access_token_decoded = tokens_decoded.access_token

    -- introspection of opaque access token
    if type(access_token_decoded) ~= "table" then
      log(DEBUG, "[openid-connect] opaque bearer token was provided")

      if auth_method_kong_oauth2 then
        log(DEBUG, "[openid-connect] trying to find matching kong oauth2 token")
        access_token_introspected, credential, mapped_consumer = cache.oauth2.load(access_token_decoded)

        if access_token_introspected then
          log(DEBUG, "[openid-connect] found matching kong oauth2 token")

        else
          log(DEBUG, "[openid-connect] matching kong oauth2 token was not found")
        end
      end

      if not access_token_introspected then
        if auth_method_introspection then
          if get_conf_arg(conf, "cache_introspection") then
            log(DEBUG, "[openid-connect] trying to authenticate using oauth2 introspection with caching enabled")
            access_token_introspected = cache.introspection.load(
              o,access_token_decoded, get_conf_arg(conf, "introspection_endpoint"), exp
            )
          else
            log(DEBUG, "[openid-connect] trying to authenticate using oauth2 introspection")

            access_token_introspected = o.token:introspect(access_token_decoded, "access_token", {
              introspection_endpoint = get_conf_arg(conf, "introspection_endpoint")
            })
          end

          if access_token_introspected then
            if access_token_introspected.active then
              log(DEBUG, "[openid-connect] authenticated using oauth2 introspection")

            else
              log(DEBUG, "[openid-connect] opaque token is not active anymore")
            end

          else
            log(DEBUG, "[openid-connect] unable to authenticate using oauth2 introspection")
          end
        end

        if not access_token_introspected or not access_token_introspected.active then
          log(DEBUG, "[openid-connect] authentication with opaque bearer token failed")
          return unauthorized(iss, err, s, anonymous)
        end

        grant_type = "introspection"

      else
        grant_type = "kong_oauth2"
      end

      expires = access_token_introspected.exp or exp

    else
      log(DEBUG, "[openid-connect] jwt bearer token was provided")

      -- additional non-standard verification of the claim against a jwt session cookie
      local jwt_session_cookie = get_conf_arg(conf, "jwt_session_cookie")
      if jwt_session_cookie then
        log(DEBUG, "[openid-connect] validating jwt claim against jwt session cookie")
        local jwt_session_cookie_value = var["cookie_" .. jwt_session_cookie]
        if not jwt_session_cookie_value or jwt_session_cookie_value == "" then
          return unauthorized(iss, "jwt session cookie was not specified for session claim verification", s, anonymous)
        end

        local jwt_session_claim = get_conf_arg(conf, "jwt_session_claim", "sid")
        local jwt_session_claim_value = access_token_decoded.payload[jwt_session_claim]

        if not jwt_session_claim_value then
          return unauthorized(
            iss, "jwt session claim (" .. jwt_session_claim .. ") was not specified in jwt access token", s, anonymous
          )
        end

        if jwt_session_claim_value ~= jwt_session_cookie_value then
          return unauthorized(
            iss, "invalid jwt session claim (" .. jwt_session_claim .. ") was specified in jwt access token", s, anonymous
          )
        end

        log(DEBUG, "[openid-connect] jwt claim matches jwt session cookie")
      end

      log(DEBUG, "[openid-connect] authenticated using jwt bearer token")

      grant_type = "bearer"
      expires = access_token_decoded.exp or exp
    end

    if auth_method_session then
      s.data = {
        client  = client_index,
        tokens  = tokens_encoded,
        expires = expires,
      }
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

        local token_headers_client = get_conf_arg(conf, "token_headers_client")
        if token_headers_client then
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
            log(DEBUG, "[openid-connect] injecting client headers to token request")
            arg.headers = token_headers
          end
        end

        if get_conf_arg(conf, "cache_tokens") then
          log(DEBUG, "[openid-connect] trying to exchange credentials using token endpoint with caching enabled")
          tokens_encoded, err, extra_headers = cache.tokens.load(o, arg, exp)

        else
          log(DEBUG, "[openid-connect] trying to exchange credentials using token endpoint")
          tokens_encoded, err, extra_headers = o.token:request(arg)
        end

        if tokens_encoded then
          log(DEBUG, "[openid-connect] exchanged credentials with tokens")
          grant_type = arg.grant_type or "authorization_code"
          args = arg
          break
        end
      end
    end

    if not tokens_encoded then
      log(DEBUG, "[openid-connect] unable to exchange credentials with tokens")
      return unauthorized(iss, err, s, anonymous)
    end

    log(DEBUG, "[openid-connect] verifying tokens")

    -- TODO: cache token verification
    tokens_decoded, err = o.token:verify(tokens_encoded, args)
    if not tokens_decoded then
      log(DEBUG, "[openid-connect] token verification failed")
      return unauthorized(iss, err, s, anonymous)

    else
      log(DEBUG, "[openid-connect] tokens verified")
    end

    expires = (tonumber(tokens_encoded.expires_in) or default_expires_in) + now

    if auth_method_session then
      s.data = {
        client  = client_index,
        tokens  = tokens_encoded,
        expires = expires,
      }

      if session_present then
        s:regenerate()

      else
        s:save()
      end
    end

  else
    -- it looks like we are using session authentication
    log(DEBUG, "[openid-connect] authenticated using session")

    grant_type = "session"
    expires = (session_data.expires or leeway)
  end

  log(DEBUG, "[openid-connect] checking for access token")
  if not tokens_encoded.access_token then
    log(DEBUG, "[openid-connect] access token was not found")
    return unauthorized(iss, "access token was not found", s, anonymous)

  else
    log(DEBUG, "[openid-connect] found access token")
  end

  expires = (expires or leeway) - leeway

  log(DEBUG, "[openid-connect] checking for access token expiration")

  if expires > now then
    log(DEBUG, "[openid-connect] access token is valid and has not expired")

    if get_conf_arg(conf, "reverify") then
      log(DEBUG, "[openid-connect] reverifying tokens")
      tokens_decoded, err = o.token:verify(tokens_encoded)
      if not tokens_decoded then
        log(DEBUG, "[openid-connect] reverifying tokens failed")
        return forbidden(iss, err, s, anonymous)

      else
        log(DEBUG, "[openid-connect] reverified tokens")
      end
    end

    if auth_method_session then
      s:start()
    end

  else
    log(DEBUG, "[openid-connect] access token has expired")

    if auth_method_refresh_token then
      -- access token has expired, try to refresh the access token before proxying
      if not tokens_encoded.refresh_token then
        return forbidden(iss, "access token cannot be refreshed in absense of refresh token", s, anonymous)
      end

      log(DEBUG, "[openid-connect] trying to refresh access token using refresh token")

      local tokens_refreshed
      local refresh_token = tokens_encoded.refresh_token
      tokens_refreshed, err = o.token:refresh(refresh_token)

      if not tokens_refreshed then
        log(DEBUG, "[openid-connect] unable to refresh access token using refresh token")
        return forbidden(iss, err, s, anonymous)

      else
        log(DEBUG, "[openid-connect] refreshed access token using refresh token")
      end

      if not tokens_refreshed.id_token then
        tokens_refreshed.id_token = tokens_encoded.id_token
      end

      if not tokens_refreshed.refresh_token then
        tokens_refreshed.refresh_token = refresh_token
      end

      log(DEBUG, "[openid-connect] verifying refreshed tokens")
      tokens_decoded, err = o.token:verify(tokens_refreshed)
      if not tokens_decoded then
        log(DEBUG, "[openid-connect] unable to verify refreshed tokens")
        return forbidden(iss, err, s, anonymous)

      else
        log(DEBUG, "[openid-connect] verified refreshed tokens")
      end

      tokens_encoded = tokens_refreshed

      expires = (tonumber(tokens_encoded.expires_in) or default_expires_in) + now

      if auth_method_session then
        s.data = {
          client  = client_index,
          tokens  = tokens_encoded,
          expires = expires,
        }

        s:regenerate()
      end

    else
      return forbidden(iss, "access token has expired and could not be refreshed", s, anonymous)
    end
  end

  local is_anonymous

  if not mapped_consumer then
    local consumer_claim = get_conf_arg(conf, "consumer_claim")
    if consumer_claim then
      log(DEBUG, "[openid-connect] trying to find kong consumer")

      local consumer_by = get_conf_arg(conf, "consumer_by")

      if not tokens_decoded then
        log(DEBUG, "[openid-connect] decoding tokens")
        tokens_decoded, err = o.token:decode(tokens_encoded)
      end

      if tokens_decoded then
        log(DEBUG, "[openid-connect] decoded tokens")

        local id_token = tokens_decoded.id_token
        if id_token then
          log(DEBUG, "[openid-connect] trying to find consumer using id token")
          mapped_consumer, err = consumer(id_token, consumer_claim, false, consumer_by)
          if not mapped_consumer then
            log(DEBUG, "[openid-connect] trying to find consumer using access token")
            mapped_consumer = consumer(tokens_decoded.access_token, consumer_claim, false, consumer_by)
          end

        else
          log(DEBUG, "[openid-connect] trying to find consumer using access token")
          mapped_consumer, err = consumer(tokens_decoded.access_token, consumer_claim, false, consumer_by)
        end
      end

      if not mapped_consumer and access_token_introspected then
        log(DEBUG, "[openid-connect] trying to find consumer using introspection response")
        mapped_consumer, err = consumer(access_token_introspected, consumer_claim, false, consumer_by)
      end

      if not mapped_consumer then
        log(DEBUG, "[openid-connect] kong consumer was not found")
        if not anonymous then
          if err then
            return forbidden(iss, "consumer was not found (" .. err .. ")", s, anonymous)

          else
            return forbidden(iss, "consumer was not found", s, anonymous)
          end
        end

        log(DEBUG, "[openid-connect] trying with anonymous kong consumer")

        is_anonymous = true

        local consumer_token = {
          payload = {
            id = anonymous
          }
        }

        mapped_consumer, err = consumer(consumer_token, "id", true, "id")
        if not mapped_consumer then
          log(DEBUG, "[openid-connect] anonymous kong consumer was not found")

          if err then
            return unexpected("anonymous consumer was not found (" .. err .. ")")

          else
            return unexpected("anonymous consumer was not found")
          end

        else
          log(DEBUG, "[openid-connect] found anonymous kong consumer")
        end

      else
        log(DEBUG, "[openid-connect] found kong consumer")
      end

    else
      if anonymous then
        log(DEBUG, "[openid-connect] trying to set anonymous kong consumer")

        is_anonymous = true

        local consumer_token = {
          payload = {
            id = anonymous
          }
        }

        mapped_consumer, err = consumer(consumer_token, "id", true, "id")
        if not mapped_consumer then
          log(DEBUG, "[openid-connect] anonymous kong consumer was not found")

          if err then
            return unexpected("anonymous consumer was not found (" .. err .. ")")

          else
            return unexpected("anonymous consumer was not found")
          end

        else
          log(DEBUG, "[openid-connect] found anonymous kong consumer")
        end
      end
    end
  end

  if mapped_consumer then
    log(DEBUG, "[openid-connect] setting kong consumer context and headers")

    local head = constants.HEADERS

    ngx.ctx.authenticated_consumer = mapped_consumer

    if credential then
      ngx.ctx.authenticated_credential = credential

    else
      if is_anonymous then
        set_header(head.ANONYMOUS, true)

      else
        set_header(head.ANONYMOUS, nil)

        ngx.ctx.authenticated_credential = {
          consumer_id = mapped_consumer.id
        }
      end
    end

    set_header(head.CONSUMER_ID,        mapped_consumer.id)
    set_header(head.CONSUMER_CUSTOM_ID, mapped_consumer.custom_id)
    set_header(head.CONSUMER_USERNAME,  mapped_consumer.username)

  else
    log(DEBUG, "[openid-connect] removing possible remnants of anonymous")

    ngx.ctx.authenticated_consumer   = nil
    ngx.ctx.authenticated_credential = nil

    local head = constants.HEADERS

    set_header(head.CONSUMER_ID,        nil)
    set_header(head.CONSUMER_CUSTOM_ID, nil)
    set_header(head.CONSUMER_USERNAME,  nil)

    set_header(head.ANONYMOUS,          nil)
  end

  -- remove session cookie from the upstream request?
  if auth_method_session then
    log(DEBUG, "[openid-connect] hiding session cookie from upstream")
    s:hide()
  end

  -- here we replay token endpoint request response headers, if any
  if extra_headers and grant_type then
    local replay_for = get_conf_arg(conf, "token_headers_grants")
    if replay_for then
      log(DEBUG, "[openid-connect] replaying token endpoint request headers")
      local replay_prefix = get_conf_arg(conf, "token_headers_prefix")
      for _, v in ipairs(replay_for) do
        if v == grant_type then
          local replay_headers = get_conf_arg(conf, "token_headers_replay")
          if replay_headers then
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

  log(DEBUG, "[openid-connect] setting upstream and downstream headers")

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
      if get_conf_arg(conf, "cache_user_info") then
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
        -- TODO: cache token decoded
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

  local login_action = get_conf_arg(conf, "login_action")
  if login_action == "response" or login_action == "redirect" then
    local has_login_method

    local login_methods = get_conf_arg(conf, "login_methods", { "authorization_code" })
    for _, login_method in ipairs(login_methods) do
      if grant_type == login_method then
        has_login_method = true
        break
      end
    end

    if has_login_method then
      if login_action == "response" then
        local login_response = {}

        local login_tokens = get_conf_arg(conf, "login_tokens")
        if login_tokens then
          log(DEBUG, "[openid-connect] adding login tokens to response")
          for _, name in ipairs(login_tokens) do
            if tokens_encoded[name] then
              login_response[name] = tokens_encoded[name]
            end
          end
        end

        log(DEBUG, "[openid-connect] login with response login action")
        return success(login_response)

      elseif login_action == "redirect" then
        if login_redirect_uri then
          local ruri, i = { login_redirect_uri }, 2

          local login_tokens = get_conf_arg(conf, "login_tokens")
          if login_tokens then
            log(DEBUG, "[openid-connect] adding login tokens to redirect uri")

            local login_redirect_mode   = get_conf_arg(conf, "login_redirect_mode", "fragment")
            local redirect_params_added = false

            if login_redirect_mode == "query" then
              if find(login_redirect_uri, "?", 1, true) then
                redirect_params_added = true
              end

            else
              if find(login_redirect_uri, "#", 1, true) then
                redirect_params_added = true
              end
            end

            for _, name in ipairs(login_tokens) do
              if tokens_encoded[name] then
                if not redirect_params_added then
                  if login_redirect_mode == "query" then
                    ruri[i] = "?"

                  else
                    ruri[i] = "#"
                  end

                  redirect_params_added = true

                else
                  ruri[i] = "&"
                end

                ruri[i + 1] = name
                ruri[i + 2] = "="
                ruri[i + 3] = tokens_encoded[name]

                i = i + 4
              end
            end
          end

          header["Cache-Control"] = "no-cache, no-store"
          header["Pragma"]        = "no-cache"

          log(DEBUG, "[openid-connect] login with redirect login action")
          return redirect(concat(ruri))
        end
      end
    end
  end

  log(DEBUG, "[openid-connect] proxying to upstream")
  -- proxies to upstream
end


OICHandler.PRIORITY = 1000
OICHandler.VERSION  = cache.version


return OICHandler
