-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local http          = require "resty.http"
local x509          = require "resty.openssl.x509"
local codec         = require "kong.openid-connect.codec"
local debug         = require "kong.openid-connect.debug"
local utils         = require "kong.openid-connect.utils"
local jwa           = require "kong.openid-connect.jwa"
local nyi           = require "kong.openid-connect.nyi"
local set           = require "kong.openid-connect.set"
local claimshandler = require "kong.openid-connect.claims"
local certificate   = require "kong.openid-connect.certificate"
local dpop          = require "kong.openid-connect.dpop"


local setmetatable  = setmetatable
local credentials   = codec.credentials
local encode_args   = codec.args.encode
local base64url     = codec.base64url
local base64        = codec.base64
local tonumber      = tonumber
local tostring      = tostring
local ipairs        = ipairs
local pairs         = pairs
local concat        = table.concat
local lower         = string.lower
local json          = codec.json
local time          = ngx.time
local type          = type
local byte          = string.byte
local sub           = string.sub
local get_scopes    = utils.get_scopes


local SLASH = byte("/")


local TOKEN_TYPES = {
  bearer        = "bearer",
  bearer_token  = "bearer",
  access        = "bearer",
  access_token  = "bearer",
  at            = "bearer",
  act           = "bearer",
  id            = "id",
  id_token      = "id",
  it            = "id",
  idt           = "id",
  refresh       = "refresh",
  refresh_token = "refresh",
  rt            = "refresh",
  rft           = "refresh",
  offline       = "refresh",
  offline_token = "refresh",
  ot            = "refresh",
}


local ISSUER = {
  ["https://www.paypalobjects.com"] = "https://api.paypal.com",
}


local INTROSPECT = {
  ["https://accounts.google.com"] = function(token, hint, args)
    args = args or {}

    if hint == "access_token" then
      args.access_token = token
      return args
    end

    if hint == "id_token" then
      args.id_token = token
      return args
    end

    args.token_handle = token
    return args
  end,
}


local REVOKE = {
}


local function url_array_fmt(arr)
  if type(arr) ~= "table" then
    return "unknown error (not a table)"
  end

  return concat(arr, " ")
end

local function copy(original)
  local copied = {}
  for key, value in pairs(original) do
    copied[key] = value
  end
  return copied
end


local token = {}


token.__index = token


function token.new(oic)
  return setmetatable({ oic = oic }, token)
end


function token:request(options)
  options = options or {}

  local opts = self.oic.options
  local conf = self.oic.configuration

  local endpoint = options.token_endpoint or
                      opts.token_endpoint or
                      conf.token_endpoint

  if not endpoint then
    return nil, "token endpoint was not specified"
  end

  local args = options.args or opts.args or {}

  local code          = options.code          or args.code          or opts.code
  local client_id     = options.client_id     or args.client_id     or opts.client_id
  local client_secret = options.client_secret or args.client_secret or opts.client_secret
  local client_auth   = options.client_auth   or args.client_auth   or opts.client_auth
  local client_jwk    = options.client_jwk    or args.client_jwk    or opts.client_jwk
  local client_alg    = options.client_alg    or args.client_alg    or opts.client_alg
  local username      = options.username      or args.username      or opts.username
  local password      = options.password      or args.password      or opts.password
  local assertion     = options.assertion     or args.assertion     or opts.assertion
  local refresh_token = options.refresh_token or args.refresh_token or opts.refresh_token

  local headers       = options.headers       or opts.headers       or {}

  local verify_parameters = true
  if options.verify_parameters ~= nil then
    verify_parameters = not not options.verify_parameters
  elseif opts.verify_parameters ~= nil then
    verify_parameters = not not opts.verify_parameters
  end

  local grant_type = options.grant_type or args.grant_type or opts.grant_type
  if not grant_type then
    if code then
      grant_type = "authorization_code"

    elseif refresh_token then
      grant_type = "refresh_token"

    elseif username and password then
      grant_type = "password"

    elseif assertion then
      grant_type = "urn:ietf:params:oauth:grant-type:jwt-bearer"

    elseif client_id and client_secret then
      grant_type = "client_credentials"

    else
      return nil, "invalid grant type"
    end
  end

  if verify_parameters then
    local grant_types = options.grant_types_supported or
                           opts.grant_types_supported or
                           conf.grant_types_supported
    if grant_types then
      if not set.has(grant_type, grant_types) then
        return nil, "invalid or unsupported grant type (" .. grant_type .. ")"
      end
    end
  end

  args.grant_type = grant_type

  local tls_client_auth_enabled = not not (options.tls_client_auth_cert or opts.tls_client_auth_cert)

  local redirect_uri = options.redirect_uri or args.redirect_uri or opts.redirect_uri
  if not redirect_uri then
    local redirect_uris = options.redirect_uris or args.redirect_uris or opts.redirect_uris
    if type(redirect_uris) == "table" and redirect_uris[1] then
      redirect_uri = redirect_uris[1]
    else
      return nil, "redirect uri was not specified"
    end
  end
  args.redirect_uri = redirect_uri

  if args.grant_type == "authorization_code" then
    if not code then
      return nil, "authorization code was not specified"
    end

    args.code = code

    local require_proof_key_for_code_exchange = options.require_proof_key_for_code_exchange
    if require_proof_key_for_code_exchange == nil then
      require_proof_key_for_code_exchange = opts.require_proof_key_for_code_exchange
      if require_proof_key_for_code_exchange == nil then
        -- this is a non-standard metadata key (not sure if any idp supports it)
        require_proof_key_for_code_exchange = conf.require_proof_key_for_code_exchange
      end
    end

    local code_verifier = options.code_verifier or args.code_verifier
    if require_proof_key_for_code_exchange == true and not code_verifier then
      return nil, "missing code verifier for the proof key for code exchange"
    end

    if require_proof_key_for_code_exchange == false then
      args.code_verifier = nil
    else
      args.code_verifier = code_verifier
    end

    if not client_secret then
      args.client_id = client_id
    end

  elseif args.grant_type == "refresh_token" then
    args.refresh_token = refresh_token

    if not client_secret then
      args.client_id = client_id
    end

  elseif args.grant_type == "client_credentials" then
    if not client_id then
      return nil, "client id was not specified"
    end

    if not client_secret then
      return nil, "client secret was not specified"
    end

    -- let's disable these
    client_auth = nil
    client_jwk = nil
    -- mtls client auth is not allowed for client_credentials grant type
    tls_client_auth_enabled = false

    local scope = get_scopes(options, args, opts, conf, verify_parameters)
    if scope then
      args.scope = scope
    end

  elseif args.grant_type == "password" then
    if not username then
      return nil, "username was not specified"
    end

    if not password then
      return nil, "password was not specified"
    end

    args.username = username
    args.password = password

    local scope = get_scopes(options, args, opts, conf, verify_parameters)
    if scope then
      args.scope = scope
    end

  elseif args.grant_type == "urn:ietf:params:oauth:grant-type:jwt-bearer" then
    if not assertion then
      return nil, "assertion was not specified"
    end

    args.assertion = assertion
  end

  local ssl_client_cert, ssl_client_priv_key, client_cert_digest
  if client_id and (client_secret or client_jwk or tls_client_auth_enabled) then
    local methods

    local token_endpoint_auth_method = options.token_endpoint_auth_method or
                                          args.token_endpoint_auth_method or
                                          opts.token_endpoint_auth_method or client_auth

    if token_endpoint_auth_method then
      if args.grant_type == "client_credentials"
      or args.grant_type == "urn:ietf:params:oauth:grant-type:jwt-bearer"
      then
        if token_endpoint_auth_method ~= "none" and
           token_endpoint_auth_method ~= "private_key_jwt" then
          methods = { token_endpoint_auth_method }
        end

      else
        methods = { token_endpoint_auth_method }
      end
    end

    if not methods then
      methods = options.token_endpoint_auth_methods_supported or
                   opts.token_endpoint_auth_methods_supported or
                   conf.token_endpoint_auth_methods_supported

      if not methods then
        if not client_secret then
          methods = { "private_key_jwt" }

        else
          methods = { "client_secret_basic" }
        end
      end
    end

    if set.has("client_secret_basic", methods) and client_secret then
      local authz, err = credentials.encode(client_id, client_secret)
      if not authz then
        return nil, err
      end
      headers["Authorization"] = "Basic " .. authz

    elseif set.has("client_secret_post", methods) and client_secret then
      args.client_id = client_id
      args.client_secret = client_secret

    elseif set.has("client_secret_jwt", methods) and client_secret then
      local signed_token, err = utils.generate_client_secret_jwt(client_id, client_secret, endpoint, client_alg)
      if not signed_token then
        return nil, err
      end

      -- E.g. Okta errors if you give client_id, even when it is optional standard argument
      --args.client_id = client_id
      args.client_id = nil
      args.client_assertion = signed_token
      args.client_assertion_type = "urn:ietf:params:oauth:client-assertion-type:jwt-bearer"

    elseif set.has("private_key_jwt", methods) and client_jwk then
      local signed_token, err = utils.generate_private_key_jwt(client_id, client_jwk, endpoint)
      if not signed_token then
        return nil, err
      end

      -- E.g. Okta errors if you give client_id, even when it is optional standard argument
      --args.client_id = client_id
      args.client_id = nil
      args.client_assertion = signed_token
      args.client_assertion_type = "urn:ietf:params:oauth:client-assertion-type:jwt-bearer"

    elseif (
        set.has("tls_client_auth", methods) or set.has("self_signed_tls_client_auth", methods)
      ) and tls_client_auth_enabled then

      if not client_id then
        return nil, "client id must be specified for tls client auth method"
      end

      args.client_id = client_id

      local opts_tls_client_cert = options.tls_client_auth_cert or opts.tls_client_auth_cert
      local opts_tls_client_key  = options.tls_client_auth_key  or opts.tls_client_auth_key

      if not opts_tls_client_cert or not opts_tls_client_key then
        return nil, "client certificate and key are required for tls authentication"
      end

      local err
      ssl_client_cert, err, client_cert_digest = certificate.load_certificate(opts_tls_client_cert)
      if not ssl_client_cert then
        return nil, "loading client certificate failed: " .. err
      end

      local key
      key, err = certificate.load_key(opts_tls_client_key)
      if not key then
        return nil, "loading client key failed: " .. err
      end
      ssl_client_priv_key = key

      -- token endpoint mtls alias override
      endpoint = options.mtls_token_endpoint or opts.mtls_token_endpoint                    or
                 (conf.mtls_endpoint_aliases and conf.mtls_endpoint_aliases.token_endpoint) or
                 endpoint

    elseif set.has("none", methods) then
      if not args.client_id then
        if not client_id then
          return nil, "client id was not specified"
        end
        args.client_id = client_id
      end

    else
      return nil, "supported token endpoint authentication method was not found"
    end
  end

  headers["Content-Type"] = "application/x-www-form-urlencoded; charset=utf-8"

  local keepalive
  if options.keepalive ~= nil then
    keepalive = not not options.keepalive
  elseif opts.keepalive ~= nil then
    keepalive = not not opts.keepalive
  else
    keepalive = true
  end

  local ssl_verify
  if options.ssl_verify ~= nil then
    ssl_verify = not not options.ssl_verify
  elseif opts.ssl_verify ~= nil then
    ssl_verify = not not opts.ssl_verify
  else
    ssl_verify = false
  end

  local pool
  if tls_client_auth_enabled and ssl_client_cert then
    local tls_client_auth_ssl_verify = options.tls_client_auth_ssl_verify or
                                       opts.tls_client_auth_ssl_verify
    ssl_verify = not not tls_client_auth_ssl_verify

    local err
    pool, err = utils.pool_key(endpoint, ssl_verify, client_cert_digest)
    if not pool then
      debug(err)
    end
  end

  local body = encode_args(args)
  local params = {
    version             = tonumber(options.http_version) or
                          tonumber(opts.http_version),
    method              = "POST",
    headers             = headers,
    body                = body,
    keepalive           = keepalive,
    ssl_verify          = ssl_verify,
    ssl_client_cert     = ssl_client_cert,
    ssl_client_priv_key = ssl_client_priv_key,
    pool                = pool,
  }

  local httpc = http.new()

  local timeout = options.timeout or opts.timeout
  if timeout then
    if httpc.set_timeouts then
      httpc:set_timeouts(timeout, timeout, timeout)

    else
      httpc:set_timeout(timeout)
    end
  end

  if httpc.set_proxy_options and (options.http_proxy  or
                                  options.https_proxy or
                                  opts.http_proxy     or
                                  opts.https_proxy) then
    httpc:set_proxy_options({
      http_proxy                = options.http_proxy                or opts.http_proxy,
      http_proxy_authorization  = options.http_proxy_authorization  or opts.http_proxy_authorization,
      https_proxy               = options.https_proxy               or opts.https_proxy,
      https_proxy_authorization = options.https_proxy_authorization or opts.https_proxy_authorization,
      no_proxy                  = options.no_proxy                  or opts.no_proxy,
    })
  end

  local res, err, tokens

  res = httpc:request_uri(endpoint, params)
  if not res then
    res, err = httpc:request_uri(endpoint, params)
    if not res then
      return nil, err
    end
  end

  local status = res.status
  body = res.body

  if status ~= 200 then
    if body and body ~= "" then
      debug(body)
    end
    return nil, "invalid status code received from the token endpoint (" .. status .. ")"
  end

  if body and body ~= "" then
    local token_format = options.token_format or opts.token_format or nil
    if token_format == "string" then
      return body, nil, res.headers

    elseif token_format == "base64" then
      return base64.encode(body), nil, res.headers

    elseif token_format == "base64url" then
      return base64url.encode(body), nil, res.headers

    else
      tokens, err = json.decode(body)
      if not tokens then
        return nil, "unable to json decode token endpoint response (" .. err .. ")"
      end

      if type(tokens) ~= "table" then
        return nil, "invalid token endpoint response received"
      end

      return tokens, nil, res.headers
    end
  end

  return nil, "token endpoint did not return response body"
end


function token:refresh(refresh_token, options)
  options = options or {}
  options.refresh_token = refresh_token
  options.grant_type    = "refresh_token"
  return self:request(options)
end


function token:decode(tokens, options)
  options = options or {}

  local opts = self.oic.options

  local verify_claims = true
  if options.verify_claims ~= nil then
    verify_claims = not not options.verify_claims
  elseif opts.verify_claims ~= nil then
    verify_claims = not not opts.verify_claims
  end

  if type(tokens) == "table" then
    if tokens.decoded then
      return tokens
    end

    local token_type = tokens.token_type
    if token_type then
      token_type = TOKEN_TYPES[lower(token_type)] or token_type
      -- TODO: add support for mac tokens and possibly for other token types as well
      if token_type ~= "bearer" then
        return nil, "invalid token type specified for tokens (" .. token_type .. ")"
      end
    end

    local tokens_needed = options.tokens or {}

    if type(tokens_needed) ~= "table" then
      tokens_needed = { tokens_needed }
    end

    for _, tok in ipairs(tokens_needed) do
      if not tokens[tok] then
        return nil, tok .. " was not specified"
      end
    end

    local err
    local idt = tokens.id_token
    local act = tokens.access_token
    local rft = tokens.refresh_token

    if idt then
      options.token_type   = "id"
      options.access_token = act or options.access_token
      idt, err = self:decode(idt, options)
      if not idt then
        return nil, err
      end
      -- we need a decoded ID_TOKEN and optionally and encoded access_token
      local cl_handler = claimshandler.new(idt, act, self)
      if options.resolve_distributed_claims or opts.resolve_distributed_claims then
        -- currently we expect to find distributed claims only in ID tokens
        if idt then
          local d_success, d_resolve_err = cl_handler:resolve_distributed_claims()
          if not d_success then
            return d_success, d_resolve_err
          end
        end
      end

      if options.resolve_aggregated_claims or opts.resolve_aggregated_claims then
        -- currently we expect to find aggregated claims only in ID tokens
        if idt then
          local a_success, a_resolve_err = cl_handler:resolve_aggregated_claims()
          if not a_success then
            return a_success, a_resolve_err
          end
        end
      end
    end

    if act then
      options.token_type = "bearer"
      act, err = self:decode(act, options)
      if not act then
        return nil, err
      end
    end

    if rft then
      options.token_type = "refresh"
      rft, err = self:decode(rft, options)
      if not rft then
        return nil, err
      end
    end

    local tks = {
      id_token      = idt,
      access_token  = act,
      refresh_token = rft,
    }

    for i, tok in ipairs(tokens) do
      tok, err = self:decode(tok, options)
      if not tok then
        return nil, err
      end

      tks[i] = tok
    end

    return tks

  elseif tokens then
    local ok
    local err
    local jwt = self.oic.jwt
    local tok = tokens

    local token_type
    if options.token_type then
      token_type = TOKEN_TYPES[lower(options.token_type)]
    end

    local jwt_type = jwt.type(tok)
    if jwt_type == "JWS" then
      if token_type == "bearer" then
        if options.ignore_signature == true or opts.ignore_signature == true then
          local new_options = copy(options)
          new_options.verify_signature = false
          tok, err = jwt:decode(tokens, new_options)
        else
          tok, err = jwt:decode(tokens, options)
        end

      elseif token_type == "refresh" then
        -- we don't verify signature of refresh tokens anymore
        local new_options = copy(options)
        new_options.verify_signature = false
        tok = jwt:decode(tokens, new_options)
        if not tok then
          -- we are not that strict of refresh token (it can be opaque to us)
          return tokens
        end

      else
        tok, err = jwt:decode(tokens, options)
      end

      if not tok then
        return nil, err
      end

      tok.decoded = true

      if verify_claims then
        ok, err = self:verify(tok, options)
        if not ok then
          return nil, err
        end
      end

    else
      -- access token should be treated as opaque and should be introspected
      -- id token should always be a jwt
      if token_type == "id" then
        return nil, "invalid id token specified"
      end
    end

    return tok
  end

  return nil, "token was not specified"
end


local function verify_x5t(claim_x5t_s256, client_cert_pem)
  if not claim_x5t_s256 then
    return nil, "x5t#S256 claim required but not found"
  end

  if not client_cert_pem then
    return nil, "client certificate was not specified"
  end

  local client_cert, err = x509.new(client_cert_pem)
  if not client_cert then
    return nil, "failed to read client certificate: " .. err
  end

  local x5t_s256 = assert(client_cert:digest("SHA256"))
  local x5t_s256_encoded = assert(base64url.encode(x5t_s256))

  if claim_x5t_s256 ~= x5t_s256_encoded then
    return nil, "the client certificate thumbprint does not match the x5t#S256 claim"
  end

  return true
end


function token:verify_client_mtls(claims, client_cert_pem)
  local cnf = claims and claims.cnf
  local claim_x5t_s256 = cnf and cnf["x5t#S256"]

  -- mandatory verification, or optional verification for tokens with the claim
  local ok, err = verify_x5t(claim_x5t_s256, client_cert_pem)
  if not ok then
    return false, "invalid_token", err
  end

  return true
end


function token:verify(tokens, options)
  options = options or {}

  if type(tokens) ~= "table" then
    return nil, "invalid token was specified"
  end

  local opts = self.oic.options

  local verify_claims = true
  if options.verify_claims ~= nil then
    verify_claims = not not options.verify_claims
  elseif opts.verify_claims ~= nil then
    verify_claims = not not opts.verify_claims
  end

  if not tokens.decoded then
    return self:decode(tokens, options)
  end

  local conf = self.oic.configuration

  local now = time()
  local lwy = tonumber(options.leeway    or opts.leeway)   or 0

  local client_id    = options.client_id or opts.client_id
  local audience     = options.audience  or opts.audience
  local clients      = options.clients   or opts.clients   or client_id
  local max_age      = options.max_age   or opts.max_age
  local domains      = options.domains   or opts.domains
  local claims       = options.claims    or opts.claims
  local issuers      = options.issuers   or opts.issuers
  local issuer       = conf.issuer

  local access_token = options.access_token
  local code         = options.code
  local nonce        = options.nonce

  if clients and type(clients) ~= "table" then
    clients = { clients }
  end

  if audience and type(audience) ~= "table" then
    audience = { audience }
  end

  local header  = tokens.header  or {}
  local payload = tokens.payload or {}

  local token_type = TOKEN_TYPES[lower(tostring(options.token_type))] or
                     TOKEN_TYPES[lower(tostring(payload.typ))]

  local cls
  local token_name

  if token_type == "id" then
    if options.token_type and options.token_type ~= "id" then
      return nil, "invalid token type (" .. token_type .. ") specified, " .. options.token_type .. " was expected"
    end

    token_name = "id token"

    if claims then
      cls = claims.id_token or claims

    else
      cls = { "iss", "sub", "aud", "exp", "iat" }

      local i = 5

      if access_token and payload.at_hash then
        i = i + 1
        cls[i] = "at_hash"
      end

      if code and payload.c_hash then
        i = i + 1
        cls[i] = "c_hash"
      end

      if max_age then
        i = i + 1
        cls[i] = "auth_time"
      end

      if domains then
        i = i + 1
        cls[i] = "hd"
      end

      if payload.nbf then
        i = i + 1
        cls[i] = "nbf"
      end

      if payload.azp then
        i = i + 1
        cls[i] = "azp"
      end
    end

  elseif token_type == "bearer" then
    if options.token_type and options.token_type ~= "bearer" then
      return nil, "invalid token type (" .. token_type .. ") specified, " .. options.token_type .. " was expected"
    end

    token_name = "access token"

    if claims then
      cls = claims.access_token or claims

    else
      cls = {}

      local i = 0

      if payload.iss then
        i = i + 1
        cls[i] = "iss"
      end

      if payload.exp then
        i = i + 1
        cls[i] = "exp"
      end

      if max_age then
        i = i + 1
        cls[i] = "auth_time"
      end

      if payload.nbf then
        i = i + 1
        cls[i] = "nbf"
      end

      if payload.iat then
        i = i + 1
        cls[i] = "iat"
      end
    end

  elseif token_type == "refresh" then
    if options.token_type and options.token_type ~= "refresh" then
      return nil, "invalid token type (" .. token_type .. ") specified, " .. options.token_type .. " was expected"
    end

    token_name = "refresh token"

    if claims then
      cls = claims.refresh_token or claims

    else
      cls = {}

      local i = 0

      if payload.iss then
        i = i + 1
        cls[i] = "iss"
      end

      if payload.exp then
        i = i + 1
        cls[i] = "exp"
      end

      if max_age then
        i = i + 1
        cls[i] = "auth_time"
      end

      if payload.nbf then
        i = i + 1
        cls[i] = "nbf"
      end

      if payload.iat then
        i = i + 1
        cls[i] = "iat"
      end
    end

  else
    token_name = "unknown token"

    if claims then
      cls = claims

    else
      cls = {}

      local i = 0

      if payload.iss then
        i = i + 1
        cls[i] = "iss"
      end

      if payload.exp then
        i = i + 1
        cls[i] = "exp"
      end
    end
  end

  local verify_nonce = true
  if options.verify_nonce ~= nil then
    verify_nonce = not not options.verify_nonce
  elseif opts.verify_nonce ~= nil then
    verify_nonce = not not opts.verify_nonce
  end

  if verify_nonce then
    if nonce then
      if token_type == "id" or payload.nonce then
        if payload.nonce ~= nonce then
          if payload.nonce and nonce then
            return nil, "invalid nonce (" .. payload.nonce .. ") specified for " .. token_name ..
                         ", " .. nonce .. " was expected"
          elseif payload.nonce then
            return nil, "invalid nonce (" .. payload.nonce .. ") specified for " .. token_name ..
                        ", nonce was not expected"
          elseif nonce then
            return nil, "invalid nonce (missing) specified for " .. token_name ..
                        ", " .. nonce .. " was expected"
          else
            return nil, "invalid nonce specified for " .. token_name .. ", nonce was not expected"
          end
        end
      end
    end
  end

  if verify_claims then
    for _, claim in ipairs(cls) do
      if claim == "alg" then
        if not header.alg then
          return nil, "alg claim was not specified for "  .. token_name
        end

        if token_type == "id" then
          local algs = options.id_token_signing_alg_values_supported or
                          opts.id_token_signing_alg_values_supported or
                          conf.id_token_signing_alg_values_supported
          if not set.has(header.alg, algs) then
            if header.alg then
              return nil, "invalid alg claim (" .. header.alg .. ") was specified for " .. token_name
            end
          end
        end

      elseif claim == "iss" and issuer then
        local payload_iss = payload.iss
        if payload_iss ~= issuer then
          if payload_iss ~= ISSUER[issuer] then
            if sub(payload_iss, -33) == "/.well-known/openid-configuration" then
              payload_iss = sub(payload_iss, 1, -34)

            elseif sub(payload_iss, -39) == "/.well-known/oauth-authorization-server" then
              payload_iss = sub(payload_iss, 1, -40)
            end

            local conf_iss = issuer
            if sub(conf_iss, -33) == "/.well-known/openid-configuration" then
              conf_iss = sub(conf_iss, 1, -34)

            elseif sub(conf_iss, -39) == "/.well-known/oauth-authorization-server" then
              conf_iss = sub(conf_iss, 1, -40)
            end

            if byte(payload_iss, -1) == SLASH then
              payload_iss = sub(payload_iss, 1, -2)
            end

            if byte(conf_iss, -1) == SLASH then
              conf_iss = sub(conf_iss, 1, -2)
            end

            if payload_iss ~= conf_iss then
              local found
              if type(issuers) == "table" then
                for _, alternate_issuer in ipairs(issuers) do
                  if alternate_issuer == payload.iss
                  or alternate_issuer == payload_iss
                  then
                    found = true
                    break
                  end
                end
              end

              if not found then
                return nil, "invalid issuer (" .. payload.iss .. ") was specified for " .. token_name ..
                            ", " .. url_array_fmt(issuers) .. " was expected"
              end
            end
          end
        end

      elseif claim == "sub" then
        if not payload.sub then
          return nil, "sub claim was not specified for " .. token_name
        end

      elseif claim == "aud" then
        local aud = payload.aud
        if not aud then
          return nil, "aud claim was not specified for " .. token_name
        end

        local auds

        if token_type == "id" then
          auds = clients

        else
          auds = audience
        end

        if auds then
          local present = false

          if type(aud) == "string" then
            for _, a in ipairs(auds) do
              if a == aud then
                present = true
                break
              end
            end

          elseif type(aud) == "table" then
            for _, a in ipairs(auds) do
              if set.has(a, aud) then
                present = true
                break
              end
            end
          end

          if not present then
            if type(aud) == "table" then
              aud = concat(aud, ", ")
            end

            if type(auds) == "table" then
              auds = concat(auds, ", ")
            end

            return nil, "invalid aud claim (" .. aud .. ") was specified for " .. token_name ..
                        ", " .. auds .. " was expected"
          end
        end

      elseif claim == "azp" then
        local azp = payload.azp

        local auds = clients
        if auds then
          local multiple = type(payload.aud) == "table"
          local present  = false

          if azp then
            for _, a in ipairs(auds) do
              if a == azp then
                present = true
                break
              end
            end

            if not present then
              return nil, "invalid azp claim (" .. azp .. ") was specified for " .. token_name
            end

          elseif multiple then
            return nil, "azp claim was not specified for " .. token_name
          end
        end

      elseif claim == "exp" then
        local exp = payload.exp
        if not exp then
          return nil, "exp claim was not specified for " .. token_name
        end

        if now - lwy > exp then
          if token_type == "refresh" then
            if exp ~= 0 then
              return nil, "invalid exp claim (" .. exp .. ") was specified for " .. token_name
            end

          else
            return nil, "invalid exp claim (" .. exp .. ") was specified for " .. token_name
          end
        end

      elseif claim == "iat" then
        local iat = payload.iat
        if not iat then
          return nil, "iat claim was not specified for " .. token_name
        end

        if now + lwy < iat then
          return nil, "invalid iat claim (" .. iat .. ") was specified for " .. token_name
        end

      elseif claim == "nbf" then
        local nbf = payload.nbf
        if not nbf then
          return nil, "nbf claim was not specified for " .. token_name
        end

        if now + lwy < nbf then
          return nil, "invalid nbf claim (" .. nbf .. ") was specified for " .. token_name
        end

      elseif claim == "auth_time" then
        local auth_time = payload.auth_time
        if not auth_time then
          return nil, "auth_time claim was not specified for " .. token_name
        end

        if now + lwy < auth_time then
          return nil, "invalid auth_time claim (" .. auth_time .. ") was specified for " .. token_name
        end

        if max_age then
          local age = now - auth_time
          if age - lwy > max_age then
            return nil, "invalid auth_time claim (" .. auth_time .. ") was specified for " .. token_name ..
                        " (max age)"
          end
        end

      elseif claim == "hd" then
        local hd = payload.hd
        if not hd then
          return nil, "hd claim was not specified for " .. token_name
        end

        local present = false

        if domains then
          for _, d in ipairs(domains) do
            if d == hd then
              present = true
              break
            end
          end

          if not present then
            local d = concat(domains, ", ")
            return nil, "invalid hd claim (" .. hd .. ") was specified for " .. token_name ..
                        ", " .. d .. " was expected"
          end
        end

      elseif claim == "at_hash" then
        if token_type == "id" then
          local at_hash = payload.at_hash
          if not at_hash then
            return nil, "at_hash claim was not specified for " .. token_name
          end

          if not access_token then
            return nil, "at_hash claim could not be validated in absense of access token"
          end

          local alg = header.alg or "RS256"
          local hsh, err = jwa.hash(alg, access_token)
          if not hsh then
            return nil, err
          end

          local mid = #hsh / 2

          hsh = sub(hsh, 1, mid)

          local ate = base64url.encode(hsh)

          if not ate or ate ~= at_hash then
            local ath = base64url.decode(at_hash)
            if ath and ath ~= hsh then
              ath = base64.decode(at_hash)
              if ath ~= hsh then
                return nil, "invalid at_hash claim (" .. at_hash .. ") was specified for " .. token_name
              end

            else
              ath = base64.decode(at_hash)
              if ath ~= hsh then
                return nil, "invalid at_hash claim (" .. at_hash .. ") was specified for " .. token_name
              end
            end
          end
        end

      elseif claim == "c_hash" then
        if token_type == "id" then
          local c_hash = payload.c_hash
          if not c_hash then
            return nil, "c_hash claim was not specified for " .. token_name
          end

          if not code then
            return nil, "c_hash claim could not be validated in absense of code"
          end

          local alg = header.alg or "RS256"
          local hsh, err = jwa.hash(alg, code)
          if not hsh then
            return nil, err
          end

          local mid = #hsh / 2

          hsh = sub(hsh, 1, mid)

          local che = base64url.encode(hsh)

          if not che or che ~= c_hash then
            local chh = base64url.decode(c_hash)
            if chh and chh ~= hsh then
              chh = base64.decode(c_hash)
              if chh ~= hsh then
                return nil, "invalid c_hash claim (" .. c_hash .. ") was specified for " .. token_name
              end

            else
              chh = base64.decode(c_hash)
              if chh ~= hsh then
                return nil, "invalid c_hash claim (" .. c_hash .. ") was specified for " .. token_name
              end
            end
          end
        end
      end
    end
  end

  return tokens
end


function token:introspect(tok, hint, options)
  options = options or {}

  local token_param_name = options.token_param_name or "token"

  local opts, conf, issuer

  if self.oic then
    opts = self.oic.options
    conf = self.oic.configuration

    issuer = conf.issuer
    if issuer then
      if byte(issuer, -1) == SLASH then
        issuer = sub(issuer, 1, -2)
      end
    end

  else
    opts = {}
    conf = {}
  end

  local endpoint = options.introspection_endpoint or
                      opts.introspection_endpoint or
                      conf.introspection_endpoint
  if not endpoint then
    endpoint = options.token_introspection_endpoint or
                  opts.token_introspection_endpoint or
                  conf.token_introspection_endpoint
    if not endpoint then
      return nil, "introspection endpoint was not specified"
    end
  end

  local args = options.args or opts.args or {}

  local bearer_token  = options.bearer_token  or args.bearer_token  or opts.bearer_token
  local client_id     = options.client_id     or args.client_id     or opts.client_id
  local client_secret = options.client_secret or args.client_secret or opts.client_secret
  local client_auth   = options.client_auth   or args.client_auth   or opts.client_auth
  local client_jwk    = options.client_jwk    or args.client_jwk    or opts.client_jwk
  local client_alg    = options.client_alg    or args.client_alg    or opts.client_alg
  local username      = options.username      or args.username      or opts.username
  local password      = options.password      or args.password      or opts.password
  local assertion     = options.assertion     or args.assertion     or opts.assertion

  local headers       = options.headers       or opts.headers       or {}

  local ssl_client_cert, ssl_client_priv_key, client_cert_digest

  local tls_client_auth_enabled = not not (options.tls_client_auth_cert or opts.tls_client_auth_cert)

  if not headers["Authorization"] then
    if bearer_token then
      headers["Authorization"] = "Bearer " .. bearer_token

    elseif username and password then
      local authz, err = credentials.encode(username, password)
      if not authz then
        return nil, err
      end

      headers["Authorization"] = "Basic " .. authz

    elseif assertion then
      return nyi()

    elseif client_id and (client_secret or client_jwk or tls_client_auth_enabled) then
      local auth_method = options.introspection_endpoint_auth_method or
                             args.introspection_endpoint_auth_method or
                             opts.introspection_endpoint_auth_method or client_auth

      if not auth_method then
        if not client_secret then
          auth_method = "private_key_jwt"

        else
          auth_method = "client_secret_basic"
        end
      end

      if auth_method == "client_secret_basic" then
        local authz, err = credentials.encode(client_id, client_secret)
        if not authz then
          return nil, err
        end

        headers["Authorization"] = "Basic " .. authz

      elseif auth_method == "client_secret_post" then
        args.client_id = client_id
        args.client_secret = client_secret

      elseif auth_method == "client_secret_jwt" then
        local signed_token, err = utils.generate_client_secret_jwt(client_id, client_secret, conf.issuer, client_alg)
        if not signed_token then
          return nil, err
        end

        -- E.g. Okta errors if you give client_id, even when it is optional standard argument
        --args.client_id = client_id
        args.client_id = nil
        args.client_assertion = signed_token
        args.client_assertion_type = "urn:ietf:params:oauth:client-assertion-type:jwt-bearer"

      elseif auth_method == "private_key_jwt" then
        local signed_token, err = utils.generate_private_key_jwt(client_id, client_jwk, conf.issuer)
        if not signed_token then
          return nil, err
        end

        -- E.g. Okta errors if you give client_id, even when it is optional standard argument
        --args.client_id = client_id
        args.client_id = nil
        args.client_assertion = signed_token
        args.client_assertion_type = "urn:ietf:params:oauth:client-assertion-type:jwt-bearer"

      elseif (
          auth_method == "tls_client_auth" or auth_method == "self_signed_tls_client_auth"
        ) and tls_client_auth_enabled then

        if not client_id then
          return nil, "client id must be specified for tls client auth method"
        end

        args.client_id = client_id

        local opts_tls_client_cert = options.tls_client_auth_cert or opts.tls_client_auth_cert
        local opts_tls_client_key  = options.tls_client_auth_key  or opts.tls_client_auth_key

        if not opts_tls_client_cert or not opts_tls_client_key then
          return nil, "client certificate and key are required for tls authentication"
        end

        local err
        ssl_client_cert, err, client_cert_digest = certificate.load_certificate(opts_tls_client_cert)
        if not ssl_client_cert then
          return nil, "loading client certificate failed: " .. err
        end

        local key
        key, err = certificate.load_key(opts_tls_client_key)
        if not key then
          return nil, "loading client key failed: " .. err
        end
        ssl_client_priv_key = key

        -- introspection endpoint mtls alias override
        endpoint = options.mtls_introspection_endpoint or opts.mtls_introspection_endpoint              or
                   (conf.mtls_endpoint_aliases and conf.mtls_endpoint_aliases.introspection_endpoint)   or
                   endpoint

      elseif auth_method == "none" then
        if not args.client_id then
          if not client_id then
            return nil, "client id was not specified"
          end
          args.client_id = client_id
        end

      else
        return nil, "supported introspection endpoint authentication method was not found"
      end
    end
  end

  local body = issuer and INTROSPECT[issuer]
  if body then
    args = body(tok, hint, args)

  else
    args[token_param_name] = tok
    args.token_type_hint = hint
  end

  headers["Content-Type"] = "application/x-www-form-urlencoded; charset=utf-8"

  local keepalive
  if options.keepalive ~= nil then
    keepalive = not not options.keepalive
  elseif opts.keepalive ~= nil then
    keepalive = not not opts.keepalive
  else
    keepalive = true
  end

  local ssl_verify
  if options.ssl_verify ~= nil then
    ssl_verify = not not options.ssl_verify
  elseif opts.ssl_verify ~= nil then
    ssl_verify = not not opts.ssl_verify
  else
    ssl_verify = false
  end

  local pool
  if tls_client_auth_enabled and ssl_client_cert then
    local tls_client_auth_ssl_verify = options.tls_client_auth_ssl_verify or
                                       opts.tls_client_auth_ssl_verify
    ssl_verify = not not tls_client_auth_ssl_verify

    local err
    pool, err = utils.pool_key(endpoint, ssl_verify, client_cert_digest)
    if not pool then
      debug(err)
    end
  end

  local params = {
    version             = tonumber(options.http_version) or
                          tonumber(opts.http_version),
    query               = options.query,
    method              = "POST",
    body                = encode_args(args),
    headers             = headers,
    keepalive           = keepalive,
    ssl_verify          = ssl_verify,
    ssl_client_cert     = ssl_client_cert,
    ssl_client_priv_key = ssl_client_priv_key,
    pool                = pool,
  }

  local httpc = http.new()

  local timeout = options.timeout or opts.timeout
  if timeout then
    if httpc.set_timeouts then
      httpc:set_timeouts(timeout, timeout, timeout)

    else
      httpc:set_timeout(timeout)
    end
  end

  if httpc.set_proxy_options and (options.http_proxy  or
                                  options.https_proxy or
                                  opts.http_proxy     or
                                  opts.https_proxy) then
    httpc:set_proxy_options({
      http_proxy                = options.http_proxy                or opts.http_proxy,
      http_proxy_authorization  = options.http_proxy_authorization  or opts.http_proxy_authorization,
      https_proxy               = options.https_proxy               or opts.https_proxy,
      https_proxy_authorization = options.https_proxy_authorization or opts.https_proxy_authorization,
      no_proxy                  = options.no_proxy                  or opts.no_proxy,
    })
  end

  local res = httpc:request_uri(endpoint, params)
  if not res then
    local err
    res, err = httpc:request_uri(endpoint, params)
    if not res then
      return nil, err
    end
  end

  local status = res.status
  body = res.body

  if status ~= 200 then
    if body and body ~= "" then
      debug(body)
    end
    return nil, "invalid status code received from the introspection endpoint (" .. status .. ")"
  end

  if body and body ~= "" then
    local introspection_format = options.introspection_format or opts.introspection_format or nil
    if introspection_format == "string" then
      return body, nil, res.headers

    elseif introspection_format == "base64" then
      return base64.encode(body), nil, res.headers

    elseif introspection_format == "base64url" then
      return base64url.encode(body), nil, res.headers

    else
      local tokeinfo, err = json.decode(body)
      if not tokeinfo then
        return nil, "unable to json decode introspection response (" .. err .. ")"
      end

      if type(tokeinfo) ~= "table" then
        return nil, "invalid introspection endpoint response received"
      end

      return tokeinfo, nil, res.headers
    end
  end

  return nil, "introspection endpoint did not return response body"
end


function token:revoke(tok, hint, options)
  options = options or {}

  local opts = self.oic.options or {}
  local conf = self.oic.configuration or {}
  local token_param_name = options.token_param_name or "token"

  local endpoint = options.revocation_endpoint or
                      opts.revocation_endpoint or
                      conf.revocation_endpoint
  if not endpoint then
    endpoint = options.token_revocation_endpoint or
                  opts.token_revocation_endpoint or
                  conf.token_revocation_endpoint
    if not endpoint then
      return nil, "revocation endpoint was not specified"
    end
  end

  local args = options.args or opts.args or {}

  local bearer_token  = options.bearer_token  or args.bearer_token  or opts.bearer_token
  local client_id     = options.client_id     or args.client_id     or opts.client_id
  local client_secret = options.client_secret or args.client_secret or opts.client_secret
  local client_auth   = options.client_auth   or args.client_auth   or opts.client_auth
  local client_jwk    = options.client_jwk    or args.client_jwk    or opts.client_jwk
  local client_alg    = options.client_alg    or args.client_alg    or opts.client_alg
  local username      = options.username      or args.username      or opts.username
  local password      = options.password      or args.password      or opts.password
  local assertion     = options.assertion     or args.assertion     or opts.assertion

  local headers       = options.headers       or opts.headers       or {}

  local ssl_client_cert, ssl_client_priv_key, client_cert_digest

  local tls_client_auth_enabled = not not (options.tls_client_auth_cert or opts.tls_client_auth_cert)

  if not headers["Authorization"] then
    if bearer_token then
      headers["Authorization"] = "Bearer " .. bearer_token

    elseif username and password then
      local authz, err = credentials.encode(username, password)
      if not authz then
        return nil, err
      end

      headers["Authorization"] = "Basic " .. authz

    elseif assertion then
      return nyi()

    elseif client_id and (client_secret or client_jwk or tls_client_auth_enabled) then
      local auth_method = options.revocation_endpoint_auth_method or
                             args.revocation_endpoint_auth_method or
                             opts.revocation_endpoint_auth_method or client_auth

      if not auth_method then
        if not client_secret then
          auth_method = "private_key_jwt"

        else
          auth_method = "client_secret_basic"
        end
      end

      if auth_method == "client_secret_basic" then
        local authz, err = credentials.encode(client_id, client_secret)
        if not authz then
          return nil, err
        end

        headers["Authorization"] = "Basic " .. authz

      elseif auth_method == "client_secret_post" then
        args.client_id = client_id
        args.client_secret = client_secret

      elseif auth_method == "client_secret_jwt" then
        local signed_token, err = utils.generate_client_secret_jwt(client_id, client_secret, conf.issuer, client_alg)
        if not signed_token then
          return nil, err
        end

        -- E.g. Okta errors if you give client_id, even when it is optional standard argument
        --args.client_id = client_id
        args.client_id = nil
        args.client_assertion = signed_token
        args.client_assertion_type = "urn:ietf:params:oauth:client-assertion-type:jwt-bearer"

      elseif auth_method == "private_key_jwt" then
        local signed_token, err = utils.generate_private_key_jwt(client_id, client_jwk, conf.issuer)
        if not signed_token then
          return nil, err
        end

        -- E.g. Okta errors if you give client_id, even when it is optional standard argument
        --args.client_id = client_id
        args.client_id = nil
        args.client_assertion = signed_token
        args.client_assertion_type = "urn:ietf:params:oauth:client-assertion-type:jwt-bearer"

      elseif (
          auth_method == "tls_client_auth" or auth_method == "self_signed_tls_client_auth"
        ) and tls_client_auth_enabled then

        if not client_id then
          return nil, "client id must be specified for tls client auth method"
        end

        args.client_id = client_id

        local opts_tls_client_cert = options.tls_client_auth_cert or opts.tls_client_auth_cert
        local opts_tls_client_key  = options.tls_client_auth_key  or opts.tls_client_auth_key

        if not opts_tls_client_cert or not opts_tls_client_key then
          return nil, "client certificate and key are required for tls authentication"
        end

        local err
        ssl_client_cert, err, client_cert_digest = certificate.load_certificate(opts_tls_client_cert)
        if not ssl_client_cert then
          return nil, "loading client certificate failed: " .. err
        end

        local key
        key, err = certificate.load_key(opts_tls_client_key)
        if not key then
          return nil, "loading client key failed: " .. err
        end
        ssl_client_priv_key = key

        -- revocation endpoint mtls alias override
        endpoint = options.mtls_revocation_endpoint or opts.mtls_revocation_endpoint               or
                   (conf.mtls_endpoint_aliases and conf.mtls_endpoint_aliases.revocation_endpoint) or
                   endpoint

      elseif auth_method == "none" then
        if not args.client_id then
          if not client_id then
            return nil, "client id was not specified"
          end
          args.client_id = client_id
        end

      else
        return nil, "supported revocation endpoint authentication method was not found"
      end
    end
  end

  local body

  local issuer = conf.issuer
  if issuer then
    if byte(issuer, -1) == SLASH then
      issuer = sub(issuer, 1, -2)
    end

    body = REVOKE[issuer]
  end

  if body then
    args = body(tok, hint, args)

  else
    args[token_param_name] = tok
    args.token_type_hint = hint
  end

  headers["Content-Type"] = "application/x-www-form-urlencoded; charset=utf-8"

  local keepalive
  if options.keepalive ~= nil then
    keepalive = not not options.keepalive
  elseif opts.keepalive ~= nil then
    keepalive = not not opts.keepalive
  else
    keepalive = true
  end

  local ssl_verify
  if options.ssl_verify ~= nil then
    ssl_verify = not not options.ssl_verify
  elseif opts.ssl_verify ~= nil then
    ssl_verify = not not opts.ssl_verify
  else
    ssl_verify = false
  end

  local pool
  if tls_client_auth_enabled and ssl_client_cert then
    local tls_client_auth_ssl_verify = options.tls_client_auth_ssl_verify or
                                       opts.tls_client_auth_ssl_verify
    ssl_verify = not not tls_client_auth_ssl_verify

    local err
    pool, err = utils.pool_key(endpoint, ssl_verify, client_cert_digest)
    if not pool then
      debug(err)
    end
  end

  local params = {
    version             = tonumber(options.http_version) or
                          tonumber(opts.http_version),
    query               = options.query,
    method              = "POST",
    body                = encode_args(args),
    headers             = headers,
    keepalive           = keepalive,
    ssl_verify          = ssl_verify,
    ssl_client_cert     = ssl_client_cert,
    ssl_client_priv_key = ssl_client_priv_key,
    pool                = pool,
  }

  local httpc = http.new()

  local timeout = options.timeout or opts.timeout
  if timeout then
    if httpc.set_timeouts then
      httpc:set_timeouts(timeout, timeout, timeout)

    else
      httpc:set_timeout(timeout)
    end
  end

  if httpc.set_proxy_options and (options.http_proxy  or
                                  options.https_proxy or
                                  opts.http_proxy     or
                                  opts.https_proxy) then
    httpc:set_proxy_options({
      http_proxy                = options.http_proxy                or opts.http_proxy,
      http_proxy_authorization  = options.http_proxy_authorization  or opts.http_proxy_authorization,
      https_proxy               = options.https_proxy               or opts.https_proxy,
      https_proxy_authorization = options.https_proxy_authorization or opts.https_proxy_authorization,
      no_proxy                  = options.no_proxy                  or opts.no_proxy,
    })
  end

  local res = httpc:request_uri(endpoint, params)
  if not res then
    local err
    res, err = httpc:request_uri(endpoint, params)
    if not res then
      return nil, err
    end
  end

  if res.status == 302 then
    endpoint = res.headers["Location"]
    if endpoint then
      params = {
        version             = tonumber(options.http_version) or tonumber(opts.http_version),
        method              = "GET",
        headers             = headers,
        keepalive           = keepalive,
        ssl_verify          = ssl_verify,
        ssl_client_cert     = ssl_client_cert,
        ssl_client_priv_key = ssl_client_priv_key,
        pool                = pool,
      }
      res = httpc:request_uri(endpoint, params)
      if not res then
        local err
        res, err = httpc:request_uri(endpoint, params)
        if not res then
          return nil, err
        end
      end
    end
  end

  local status = res.status
  body = res.body

  if status ~= 200 and status ~= 204 then
    if body and body ~= "" then
      debug(body)
    end
    return nil, "invalid status code received from the token revocation endpoint (" .. status .. ")"
  end

  local revocation_format = options.revocation_format or opts.revocation_format or nil
  if body and body ~= "" then
    if revocation_format == "string" then
      return body, nil, res.headers

    elseif revocation_format == "base64" then
      return base64.encode(body), nil, res.headers

    elseif revocation_format == "base64url" then
      return base64url.encode(body), nil, res.headers

    else
      local decoded = json.decode(body)
      if type(decoded) ~= "table" then
        return {}, nil, res.headers
      end

      return decoded, nil, res.headers
    end

  else
    if revocation_format == "string" or
       revocation_format == "base64" or
       revocation_format == "base64url"
    then
      return "", nil, res.headers

    else
      return {}, nil, res.headers
    end
  end
end


function token:verify_client_dpop(...)
  return dpop.verify_client_dpop(self.oic, ...)
end


return token
