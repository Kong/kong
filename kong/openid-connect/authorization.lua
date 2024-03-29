-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]


local http          = require "resty.http"


local certificate   = require "kong.openid-connect.certificate"
local random        = require "kong.openid-connect.random"
local codec         = require "kong.openid-connect.codec"
local debug         = require "kong.openid-connect.debug"
local utils         = require "kong.openid-connect.utils"
local hash          = require "kong.openid-connect.hash"
local set           = require "kong.openid-connect.set"
local nyi           = require "kong.openid-connect.nyi"


local setmetatable  = setmetatable
local credentials   = codec.credentials
local decode_args   = codec.args.decode
local encode_args   = codec.args.encode
local base64url     = codec.base64url
local get_post_args = ngx.req.get_post_args
local get_uri_args  = ngx.req.get_uri_args
local get_method    = ngx.req.get_method
local read_body     = ngx.req.read_body
local tonumber      = tonumber
local concat        = table.concat
local base64        = codec.base64
local pairs         = pairs
local lower         = string.lower
local json          = codec.json
local find          = string.find
local type          = type
local byte          = string.byte
local pcall         = pcall
local sub           = string.sub
local var           = ngx.var


local SLASH = byte("/")


local OFFLINE_FIX = {
  ["https://accounts.google.com"] = "offline",
}


local authorization = {}


authorization.__index = authorization


function authorization.new(oic)
  return setmetatable({ oic = oic }, authorization)
end


function authorization:bearer(search)
  local opts = self.oic.options

  search = search or opts.auth_methods or { "header", "body", "query" }

  if type(search) ~= "table" then
    search = { search }
  end

  if set.has("header", search) or set.has("client_secret_basic", search) then
    local act = var.http_authorization
    if act then
      local act_type = lower(sub(act, 1, 6))
      if act_type == "bearer" then
        return sub(act, 8), "header"
      end
    end
  end

  if set.has("body", search) or set.has("client_secret_post", search) then
    if find(var.content_type or "", "application/x-www-form-urlencoded", 1, true) == 1 then
      read_body()
      local args = get_post_args()
      if args then
        local act = args.access_token
        if act then
          return act, "body"
        end
      end
    end
  end

  if set.has("query", search) then
    local args = get_uri_args()
    if args then
      local act = args.access_token
      if act then
        return act, "query"
      end
    end
  end
end


function authorization:basic(search)
  local opts = self.oic.options

  search = search or opts.auth_methods or { "header", "body", "query" }

  if type(search) ~= "table" then
    search = { search }
  end

  if set.has("header", search) or set.has("client_secret_basic", search) then
    local act = var.http_authorization
    if act then
      local act_type = lower(sub(act, 1, 5))
      if act_type == "basic" then
        local encoded = sub(act, 7)
        local decoded, err = base64.decode(encoded)
        if decoded then
          local s = find(decoded, ":", 2, true)
          if s then
            local grant_type
            if find(var.content_type or "", "application/x-www-form-urlencoded", 1, true) == 1 then
              read_body()
              local args = get_post_args()
              if args.grant_type == "password" or args.grant_type == "client_credentials" then
                grant_type = args.grant_type
              end
            end

            if not grant_type then
              local args = get_uri_args()
              if args.grant_type == "password" or args.grant_type == "client_credentials" then
                grant_type = args.grant_type
              end
            end

            local identity = sub(decoded, 1, s - 1)
            local secret   = sub(decoded, s + 1)
            return identity, secret, grant_type, "header"
          end
        else
          local s = find(encoded, ":", 2, true)
          if s then
            local grant_type
            if find(var.content_type or "", "application/x-www-form-urlencoded", 1, true) == 1 then
              read_body()
              local args = get_post_args()
              if args.grant_type == "password" or args.grant_type == "client_credentials" then
                grant_type = args.grant_type
              end
            end

            if not grant_type then
              local args = get_uri_args()
              if args.grant_type == "password" or args.grant_type == "client_credentials" then
                grant_type = args.grant_type
              end
            end

            local identity = sub(encoded, 1, s - 1)
            local secret   = sub(encoded, s + 1)
            return identity, secret, grant_type, "header"
          end
        end
        return nil, err
      end
    end
  end

  if set.has("body", search) or set.has("client_secret_post", search) then
    if find(var.content_type or "", "application/x-www-form-urlencoded", 1, true) == 1 then
      read_body()
      local args = get_post_args()
      if args then
        local username = args.username
        if username then
          local password = args.password
          if password then
            return username, password, "password", "body"
          end
        end
        local client_id = args.client_id
        if client_id then
          local client_secret = args.client_secret
          if client_secret then
            return client_id, client_secret, "client_credentials", "body"
          end
        end
      end
    end
  end

  if set.has("query", search) then
    local args = get_uri_args()
    if args then
      local username = args.username
      if username then
        local password = args.password
        if password then
          return username, password, "password", "query"
        end
      end
      local client_id = args.client_id
      if client_id then
        local client_secret = args.client_secret
        if client_secret then
          return client_id, client_secret, "client_credentials", "query"
        end
      end
    end
  end
end


function authorization:state(options)
  options = options or {}

  local opts = self.oic.options
  local args = options.args or opts.args or {}

  local state = options.state or args.state
  if not state then
    local len = tonumber(options.state_len) or tonumber(opts.state_len) or 18
    local hsh = options.state_alg or opts.state_alg
    local cdc = options.state_cdc or opts.state_cdc or "base64url"

    state = random(len, hsh, cdc)
  end
  return state
end


function authorization:nonce(options)
  options = options or {}

  local opts = self.oic.options
  local args = options.args or opts.args or {}

  local nonce = options.nonce or args.nonce
  if not nonce then
    local len = tonumber(options.nonce_len) or tonumber(opts.nonce_len) or 18
    local hsh = options.nonce_alg or opts.nonce_alg
    local cdc = options.nonce_cdc or opts.nonce_cdc or "base64url"

    nonce = random(len, hsh, cdc)
  end
  return nonce
end


function authorization:pushed_authorization_request(options, args)
  options = options or {}

  local opts = self.oic.options or {}
  local conf = self.oic.configuration or {}

  local endpoint = options.pushed_authorization_request_endpoint or
                      opts.pushed_authorization_request_endpoint or
                      conf.pushed_authorization_request_endpoint

  if not endpoint then
    return nil, "pushed authorization request endpoint was not specified"
  end

  args = args or options.args or opts.args or {}

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
      local auth_method = options.pushed_authorization_request_endpoint_auth_method or
                             args.pushed_authorization_request_endpoint_auth_method or
                             opts.pushed_authorization_request_endpoint_auth_method or client_auth

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

      elseif auth_method == "none" then
        if not args.client_id then
          if not client_id then
            return nil, "client id was not specified"
          end
          args.client_id = client_id
        end

      else
        return nil, "supported pushed authorization request endpoint authentication method was not found"
      end
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
    query               = options.query,
    method              = "POST",
    body                = body,
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

  if status ~= 201 and status ~= 200 then
    if body and body ~= "" then
      debug(body)
    end
    return nil, "invalid status code received from the pushed authorization request endpoint (" .. status .. ")"
  end

  if body and body ~= "" then
    local pushed_authorization_request_format = options.pushed_authorization_request_format or
                                                   opts.pushed_authorization_request_format or nil
    if pushed_authorization_request_format == "string" then
      return body, nil, res.headers

    elseif pushed_authorization_request_format == "base64" then
      return base64.encode(body), nil, res.headers

    elseif pushed_authorization_request_format == "base64url" then
      return base64url.encode(body), nil, res.headers

    else
      local par, err = json.decode(body)
      if not par then
        return nil, "unable to json decode pushed authorization request response (" .. err .. ")"
      end

      if type(par) ~= "table" then
        return nil, "invalid pushed authorization request endpoint response received"
      end

      return par, nil, res.headers
    end
  end

  return nil, "pushed authorization request endpoint did not return response body"
end


function authorization:request(options)
  options = options or {}

  local opts = self.oic.options or {}
  local conf = self.oic.configuration or {}

  local endpoint = options.authorization_endpoint or
                      opts.authorization_endpoint or
                      conf.authorization_endpoint
  if not endpoint then
    return nil, "authorization endpoint was not specified"
  end

  local args = options.args or opts.args or {}
  if type(args) == "string" then
    args = decode_args(args)
  end
  if type(args) ~= "table" then
    return nil, "invalid arguments"
  end

  local verify_parameters = true
  if options.verify_parameters ~= nil then
    verify_parameters = not not options.verify_parameters
  elseif opts.verify_parameters ~= nil then
    verify_parameters = not not opts.verify_parameters
  end

  local response_type, count = set.new(options.response_type or
                                          args.response_type or
                                          opts.response_type or "code")

  if count > 0 then
    if verify_parameters then
      local response_types = options.response_types_supported or
                                opts.response_types_supported or
                                conf.response_types_supported
      if response_types then
        if not set.has(response_type, response_types) then
          return nil, "unsupported response types requested (" .. concat(response_type, ", ") .. ")"
        end
      end
    end

    args.response_type = concat(response_type, " ")
  end

  local scope
  scope, count = set.new(options.scope or
                            args.scope or
                            opts.scope or "openid")

  if count > 0 then
    local scopes = options.scopes_supported or
                      opts.scopes_supported or
                      conf.scopes_supported

    if scopes then
      if not set.has(scope, scopes) then
        if set.has("offline_access", scope) then
          local issuer = conf.issuer
          if issuer then
            if byte(issuer, -1) == SLASH then
              issuer = sub(issuer, 1, -2)
            end

            local access_type = OFFLINE_FIX[issuer]
            if access_type then
              scope = set.remove("offline_access", scope)
              if not args.access_type then
                args.access_type = access_type
              end
            end
          end

          if verify_parameters then
            if not set.has(scope, scopes) then
              return nil, "unsupported scopes requested (" .. concat(scope, ", ") .. ")"
            end
          end
        else
          if verify_parameters then
            return nil, "unsupported scopes requested (" .. concat(scope, ", ") .. ")"
          end
        end
      end
    end

    scope = concat(scope, " ")
    if scope ~= "" then
      args.scope = scope
    end
  end

  local redirect_uri = options.redirect_uri or
                          args.redirect_uri or
                          opts.redirect_uri
  if not redirect_uri then
    local redirect_uris = options.redirect_uris or
                             args.redirect_uris or
                             opts.redirect_uris
    if type(redirect_uris) == "table" and redirect_uris[1] then
      redirect_uri = redirect_uris[1]
    else
      return nil, "redirect uri was not specified"
    end
  end
  args.redirect_uri = redirect_uri

  local client_id = options.client_id or
                       args.client_id or
                       opts.client_id
  if not client_id then
    return nil, "client id was not specified"
  end
  args.client_id = client_id

  local state = self:state(options)
  args.state = state

  local nonce = self:nonce(options)
  args.nonce = nonce

  local code_verifier = options.code_verifier or
                           args.code_verifier

  local code_challenge_methods_supported = options.code_challenge_methods_supported or
                                              opts.code_challenge_methods_supported or
                                              conf.code_challenge_methods_supported

  local require_proof_key_for_code_exchange = options.require_proof_key_for_code_exchange
  if require_proof_key_for_code_exchange == nil then
    require_proof_key_for_code_exchange = opts.require_proof_key_for_code_exchange
    if require_proof_key_for_code_exchange == nil then
      -- this is a non-standard metadata key (not sure if any idp supports it)
      require_proof_key_for_code_exchange = conf.require_proof_key_for_code_exchange
      if require_proof_key_for_code_exchange == nil then
        -- we enable PKCE if the discovery metadata tells that it may be supported
        require_proof_key_for_code_exchange = not not code_challenge_methods_supported
      end
    end
  end

  if not require_proof_key_for_code_exchange then
    -- forcibly disable the PKCE
    args.code_challenge = nil
    args.code_challenge_method = nil
    args.code_verifier = nil

  else

    local code_challenge = options.code_challenge or
                              args.code_challenge

    local code_challenge_method = options.code_challenge_method or
                                     args.code_challenge_method

    if code_challenge then
      -- just default to S256 if user does not specify the method
      code_challenge_method = code_challenge_method or "S256"

    else
      if not code_challenge_method and code_challenge_methods_supported then
        if set.has("S512", code_challenge_methods_supported) then
          code_challenge_method = "S512"
        elseif set.has("S384", code_challenge_methods_supported) then
          code_challenge_method = "S384"
        elseif set.has("S256", code_challenge_methods_supported) then
          code_challenge_method = "S256"
        elseif set.has("plain", code_challenge_methods_supported) then
          code_challenge_method = "plain"
        end
      end

      code_challenge_method = code_challenge_method or "S256"

      if verify_parameters and code_challenge_methods_supported then
        if not set.has(code_challenge_method, code_challenge_methods_supported) then
          return nil, "unsupported code challenge method requested (" .. code_challenge_method .. ")"
        end
      end

      code_verifier = code_verifier or random(32, nil, "base64url")

      if code_challenge_method == "plain" then
        code_challenge = code_verifier
      else
        code_challenge = codec.base64url.encode(hash[code_challenge_method](code_verifier))
      end
    end

    args.code_challenge = code_challenge
    args.code_challenge_method = code_challenge_method
    args.code_verifier = nil
  end

  local display = options.display or
                     args.display or
                     opts.display
  if display then
    if verify_parameters then
      local displays = options.display_values_supported or
                          opts.display_values_supported or
                          conf.display_values_supported or { "page", "popup", "touch", "wap" }
      if not set.has(display, displays) then
        return nil, "unsupported display value requested (" .. display .. ")"
      end
    end

    args.display = display
  end

  local prompt  = options.prompt or
                     args.prompt or
                     opts.prompt
  if prompt then
    if verify_parameters then
      local prompts = { "none", "login", "consent", "select_account" }
      if not set.has(prompt, prompts) then
        return nil, "unsupported prompt value requested (" .. prompt .. ")"
      end
    end

    args.prompt = prompt
  end

  local acr = options.acr or
                 args.acr or
                 opts.acr
  if acr then
    if verify_parameters then
      local acrs = options.acr_values_supported or
                      opts.acr_values_supported or
                      conf.acr_values_supported
      if acrs then
        if not set.has(acr, acrs) then
          return nil, "unsupported acr value requested (" .. acr .. ")"
        end
      end
    end

    if type(acr) == "table" then
      acr = concat(acr, " ")
    end

    args.acr_values = acr
  end

  local amr = options.amr or
                 args.amr or
                 opts.amr
  if amr then
    if verify_parameters then
      local amrs = options.amr_values_supported or
                      opts.amr_values_supported or
                      conf.amr_values_supported
      if amrs then
        if not set.has(amr, amrs) then
          return nil, "unsupported amr value requested (" .. amr .. ")"
        end
      end
    end

    if type(amr) == "table" then
      amr = concat(amr, " ")
    end

    args.amr_values = amr
  end

  local max_age = options.max_age or
                     args.max_age or
                     opts.max_age
  if max_age then
    max_age = tonumber(max_age)
    if not max_age then
      return nil, "invalid max_age value requested"
    end
    args.max_age = max_age
  end

  local id_token_hint = options.id_token_hint or
                           args.id_token_hint or
                           opts.id_token_hint
  if id_token_hint then
    args.id_token_hint = id_token_hint
  end

  local login_hint = options.login_hint or
                        args.login_hint or
                        opts.login_hint
  if login_hint then
    args.login_hint = login_hint
  end

  local access_type = options.access_type or
                         args.access_type or
                         opts.access_type
  if access_type then
    args.access_type = access_type
  end

  local response_mode = options.response_mode or
                           args.response_mode or
                           opts.response_mode
  if response_mode then
    if verify_parameters then
      local response_modes = options.response_modes_supported or
                                opts.response_modes_supported or
                                conf.response_modes_supported

      if response_modes then
        if not set.has(response_mode, response_modes) then
          return nil, "unsupported response mode requested (" .. response_mode .. ")"
        end
      end
    end

    args.response_mode = response_mode
  end

  local hd = options.hd or args.hd or opts.hd
  if hd then
    args.hd = hd
  end

  local audience = options.audience or
                      args.audience or
                      opts.audience
  if audience then
    if type(audience) == "table" then
      args.audience = concat(audience, " ")

    else
      args.audience = audience
    end
  end

  local require_pushed_authorization_requests = options.require_pushed_authorization_requests
  if require_pushed_authorization_requests == nil then
    require_pushed_authorization_requests = opts.require_pushed_authorization_requests
    if require_pushed_authorization_requests == nil then
      require_pushed_authorization_requests = conf.require_pushed_authorization_requests
    end
  end

  if require_pushed_authorization_requests then
    local res, err = self:pushed_authorization_request(options, args)
    if not res then
      return nil, err
    end

    args = {
      client_id = client_id,
      request_uri = res.request_uri,
    }
  end

  return {
    url           = endpoint .. "?" .. encode_args(args),
    state         = state,
    nonce         = nonce,
    code_verifier = code_verifier
  }
end


function authorization:verify(options)
  options = options or {}

  local opts = self.oic.options
  local conf = self.oic.configuration
  local args = options.args

  local ok, method = pcall(get_method)
  if ok then
    method = lower(method)

    if method == "post" then
      read_body()
      if not args then
        args = get_post_args()

      else
        local post_args = get_post_args()
        for k, v in pairs(post_args) do
          if not args[k] then
            args[k] = v
          end
        end
      end
    end


    if not args then
      args = get_uri_args()

    else
      local uri_args = get_uri_args()
      for k, v in pairs(uri_args) do
        if not args[k] then
          args[k] = v
        end
      end
    end
  end

  if not args.code then
    return nil, "authorization code not present"
  end

  if not args.state then
    return nil, "authorization state not present"
  end

  if args.state ~= options.state then
    return nil, "invalid authorization state"
  end

  local iss = args.iss
  if iss and conf.issuer and iss ~= conf.issuer then
    return nil, "issuer mismatch"
  end

  if args.client_id then
    local client_id = options.client_id or opts.client_id
    if args.client_id ~= client_id then
      return nil, "client mismatch"
    end
  end

  args.nonce         = options.nonce
  args.code_verifier = options.code_verifier

  if args.id_token or args.access_token then
    options.code = args.code

    local decoded, err = self.oic.token:verify(args, options)
    if not decoded then
      return nil, err
    end

    return args, decoded
  end

  return args
end


return authorization
