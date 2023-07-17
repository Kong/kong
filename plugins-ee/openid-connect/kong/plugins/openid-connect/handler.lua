-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]


local meta = require "kong.meta"


local OICHandler = {
  PRIORITY = 1050,
  VERSION  = meta.core_version,
}


local inspect         = require "inspect"


local log             = require "kong.plugins.openid-connect.log"
local cache           = require "kong.plugins.openid-connect.cache"
local claims          = require "kong.plugins.openid-connect.claims"
local clients         = require "kong.plugins.openid-connect.clients"
local headers         = require "kong.plugins.openid-connect.headers"
local sessions        = require "kong.plugins.openid-connect.sessions"
local userinfo        = require "kong.plugins.openid-connect.userinfo"
local consumers       = require "kong.plugins.openid-connect.consumers"
local responses       = require "kong.plugins.openid-connect.responses"
local arguments       = require "kong.plugins.openid-connect.arguments"
local introspect      = require "kong.plugins.openid-connect.introspect"
local unexpected      = require "kong.plugins.openid-connect.unexpected"


local openid          = require "kong.openid-connect"
local set             = require "kong.openid-connect.set"
local codec           = require "kong.openid-connect.codec"


local kong            = kong
local ngx             = ngx
local var             = ngx.var
local time            = ngx.time
local escape_uri      = ngx.escape_uri
local tostring        = tostring
local ipairs          = ipairs
local concat          = table.concat
local lower           = string.lower
local gsub            = string.gsub
local find            = string.find
local type            = type
local sub             = string.sub
local json            = codec.json
local base64url       = codec.base64url

local TOKEN_EXPIRED_MESSAGE = "The access token expired"

local TOKEN_DECODE_OPTS = {
  verify_signature = false,
  verify_claims = false,
}


local CLIENT_CREDENTIALS_GRANT = "client_credentials"
local PASSWORD_GRANT = "password"
local REFRESH_TOKEN_GRANT = "refresh_token"
local JWT_BEARER_GRANT = "urn:ietf:params:oauth:grant-type:jwt-bearer"


local function rediscover_keys(issuer, options)
  return function()
    return cache.issuers.rediscover(issuer, options)
  end
end


local function get_authorization_args(args)
  local extra_args  = args.get_conf_args("authorization_query_args_names",
                                         "authorization_query_args_values")
  local client_args = args.get_conf_arg("authorization_query_args_client")
  if client_args then
    for _, client_arg_name in ipairs(client_args) do
      local extra_arg = args.get_uri_arg(client_arg_name)
      if extra_arg then
        if not extra_args then
          extra_args = {}
        end

        extra_args[client_arg_name] = extra_arg

      else
        extra_arg = args.get_post_arg(client_arg_name)
        if extra_arg then
          if not extra_args then
            extra_args = {}
          end

          extra_args[client_arg_name] = extra_arg
        end
      end
    end
  end

  return extra_args
end


function OICHandler.init_worker()
  clients.init_worker()
  cache.init_worker()
end


function OICHandler.access(_, conf)
  local ctx = ngx.ctx
  local args = arguments(conf)

  -- check if preflight request and whether it should be authenticated
  if not args.get_conf_arg("run_on_preflight", true) and var.request_method == "OPTIONS" then
    return
  end

  local anonymous = args.get_conf_arg("anonymous")
  if anonymous and ctx.authenticated_credential then
    -- we're already authenticated, and we're configured for using anonymous,
    -- hence we're in a logical OR between auth methods and we're already done.
    log("skipping because user is already authenticated")
    return
  end

  local client = clients.find(args)

  -- common variables
  local ok, err

  -- load discovery information
  log("loading discovery information")
  local oic, iss, secret, options
  do
    local issuer
    local issuer_uri = args.get_conf_arg("issuer")

    local discovery_options = args.get_http_opts({
      headers               = args.get_conf_args("discovery_headers_names", "discovery_headers_values"),
      rediscovery_lifetime  = args.get_conf_arg("rediscovery_lifetime", 30),
      extra_jwks_uris       = args.get_conf_arg("extra_jwks_uris"),
    })

    issuer, err = cache.issuers.load(issuer_uri, discovery_options)
    if type(issuer) ~= "table" then
      return unexpected(client, err or "discovery information could not be loaded")
    end

    options = args.get_http_opts({
      client_id                  = client.id,
      client_secret              = client.secret,
      client_auth                = client.auth,
      client_alg                 = client.alg,
      client_jwk                 = client.jwk,
      redirect_uri               = client.redirect_uri,
      issuers                    = args.get_conf_arg("issuers_allowed"),
      scope                      = args.get_conf_arg("scopes", {}),
      response_mode              = args.get_conf_arg("response_mode"),
      response_type              = args.get_conf_arg("response_type"),
      audience                   = args.get_conf_arg("audience"),
      domains                    = args.get_conf_arg("domains"),
      max_age                    = args.get_conf_arg("max_age"),
      leeway                     = args.get_conf_arg("leeway", 0),
      authorization_endpoint     = args.get_conf_arg("authorization_endpoint"),
      token_endpoint             = args.get_conf_arg("token_endpoint"),
      introspection_endpoint     = args.get_conf_arg("introspection_endpoint"),
      userinfo_endpoint          = args.get_conf_arg("userinfo_endpoint"),
      verify_parameters          = args.get_conf_arg("verify_parameters"),
      verify_nonce               = args.get_conf_arg("verify_nonce"),
      verify_signature           = args.get_conf_arg("verify_signature"),
      verify_claims              = args.get_conf_arg("verify_claims"),
      enable_hs_signatures       = args.get_conf_arg("enable_hs_signatures"),
      -- not yet implemented
      -- resolve_aggregated_claims  = args.get_conf_arg("resolve_aggregated_claims"),
      resolve_distributed_claims = args.get_conf_arg("resolve_distributed_claims"),
      rediscover_keys            = rediscover_keys(issuer_uri, discovery_options),
    })

    log("initializing library")
    oic, err = openid.new(options, issuer.configuration, issuer.keys)
    if type(oic) ~= "table" then
      return unexpected(client, err or "unable to initialize library")
    end

    iss = oic.configuration.issuer
    if not iss then
      iss = issuer_uri
      if iss then
        if sub(iss, -33) == "/.well-known/openid-configuration" then
          iss = sub(iss, 1, -34)
        elseif sub(iss, -39) == "/.well-known/oauth-authorization-server" then
          iss = sub(iss, 1, -40)
        end

        if sub(iss, -1) == "/" then
          iss = sub(iss, 1, -2)
        end
      end
    end

    secret = args.get_conf_arg("session_secret")
    if not secret then
      secret = issuer.secret
    end
  end

  -- user may want to ignore access token signature verification with
  -- some flows, e.g. azure ad sends jwt access tokens for which they
  -- don't provide a JWK in public uri
  local ignore_signature = {}
  do
    local ignore_grants = args.get_conf_arg("ignore_signature")
    if ignore_grants then
      for _, grant in ipairs(ignore_grants) do
        ignore_signature[grant] = true
      end
    end
  end

  -- initialize functions
  local session_open = sessions.new(args, secret)

  -- load enabled authentication methods
  local auth_methods = args.get_auth_methods()

  -- dynamic login redirect uri (only used with authorization code flow)
  local dynamic_login_redirect_uri
  local dynamic_login_redirect_uri_args

  -- try to open session
  local session
  local session_present
  local session_modified
  local session_regenerate
  local session_data
  local session_error
  if auth_methods.session then
    local session_secure = args.get_conf_arg("session_cookie_secure")
    if session_secure == nil then
      session_secure = kong.request.get_forwarded_scheme() == "https"
    end

    -- http_only can be configured via both parameters:
    -- session_cookie_http_only and session_cookie_httponly
    -- it defaults to true if not configured
    local http_only
    if args.get_conf_arg("session_cookie_http_only") == nil then
      http_only = args.get_conf_arg("session_cookie_httponly", true)
    else
      http_only = args.get_conf_arg("session_cookie_http_only")
    end

    session, session_error, session_present = session_open({
      cookie_name               = args.get_conf_arg("session_cookie_name", "session"),
      remember_cookie_name      = args.get_conf_arg("session_remember_cookie_name", "remember"),
      remember                  = args.get_conf_arg("session_remember", false),
      remember_rolling_timeout  = args.get_conf_arg("session_remember_rolling_timeout", 604800),
      remember_absolute_timeout = args.get_conf_arg("session_remember_absolute_timeout", 2592000),
      idling_timeout            = args.get_conf_arg("session_idling_timeout")
                               or args.get_conf_arg("session_cookie_idletime", 900),
      rolling_timeout           = args.get_conf_arg("session_rolling_timeout")
                               or args.get_conf_arg("session_cookie_lifetime", 3600),
      absolute_timeout          = args.get_conf_arg("session_absolute_timeout", 86400),
      cookie_path               = args.get_conf_arg("session_cookie_path", "/"),
      cookie_domain             = args.get_conf_arg("session_cookie_domain"),
      cookie_same_site          = args.get_conf_arg("session_cookie_same_site")
                               or args.get_conf_arg("session_cookie_samesite", "Lax"),
      cookie_http_only          = http_only,
      request_headers           = args.get_conf_arg("session_request_headers"),
      response_headers          = args.get_conf_arg("session_response_headers"),
      cookie_secure             = session_secure,
    })

    if session_present then
      session_data = session:get_data()
    end
  end

  local response = responses.new(args, ctx, iss, client, anonymous, session)

  local expose_error_code = args.get_conf_arg("expose_error_code", false)

  local function forbidden(message, description)
    return response.forbidden(message, description, expose_error_code)
  end

  local function unauthorized(message, description)
    return response.unauthorized(message, description, expose_error_code)
  end

  local proxy_despite_refresh_failure = false

  -- logout
  do
    local logout = false
    local logout_methods = args.get_conf_arg("logout_methods", { "POST", "DELETE" })
    if logout_methods then
      local request_method = var.request_method
      for _, logout_method in ipairs(logout_methods) do
        if logout_method == request_method then
          logout = true
          break
        end
      end

      if logout then
        logout = false

        local logout_query_arg = args.get_conf_arg("logout_query_arg")
        if logout_query_arg then
          logout = args.get_uri_arg(logout_query_arg) ~= nil
        end

        if logout then
          log("logout by query argument")

        else
          local logout_uri_suffix = args.get_conf_arg("logout_uri_suffix")
          if logout_uri_suffix then
            logout = sub(var.request_uri, -#logout_uri_suffix) == logout_uri_suffix
            if logout then
              log("logout by uri suffix")

            else
              local logout_post_arg = args.get_conf_arg("logout_post_arg")
              if logout_post_arg then
                logout = args.get_post_arg(logout_post_arg) ~= nil
                if logout then
                  log("logout by post argument")
                end
              end
            end
          end
        end
      end

      if logout then
        local id_token
        if session_present and type(session_data) == "table" then
          clients.reset(session_data.client, client, oic, options)

          if type(session_data.tokens) == "table" then
            id_token = session_data.tokens.id_token

            if args.get_conf_arg("logout_revoke", false) then
              local revocation_endpoint = args.get_conf_arg("revocation_endpoint")
              local revocation_endpoint_auth_method = args.get_conf_arg("revocation_endpoint_auth_method")
              if session_data.tokens.refresh_token and args.get_conf_arg("logout_revoke_refresh_token", false) then
                if revocation_endpoint then
                  log("revoking refresh token")
                  ok, err = oic.token:revoke(session_data.tokens.refresh_token, "refresh_token", {
                    revocation_endpoint = revocation_endpoint,
                    revocation_endpoint_auth_method = revocation_endpoint_auth_method,
                  })
                  if not ok and err then
                    log("revoking refresh token failed: ", err)
                  end

                else
                  ok, err = oic.token:revoke(session_data.tokens.refresh_token, "refresh_token", {
                    revocation_endpoint_auth_method = revocation_endpoint_auth_method,
                  })
                  -- call revoke here but without the user-defined recovation_endpoint
                  -- if fails, log that
                  if not ok and err then
                    log("unable to revoke refresh token: ", err)
                  end
                end
              end

              if session_data.tokens.access_token and args.get_conf_arg("logout_revoke_access_token", true) then
                if revocation_endpoint then
                  log("revoking access token")
                  ok, err = oic.token:revoke(session_data.tokens.access_token, "access_token", {
                    revocation_endpoint = revocation_endpoint,
                    revocation_endpoint_auth_method = revocation_endpoint_auth_method,
                  })
                  if not ok and err then
                    log("revoking access token failed: ", err)
                  end

                else
                  ok, err = oic.token:revoke(session_data.tokens.refresh_token, "refresh_token", {
                    revocation_endpoint_auth_method = revocation_endpoint_auth_method,
                  })
                  -- call revoke here but without the user-defined recovation_endpoint
                  -- if fails, log that
                  if not ok and err then
                    log("unable to revoke refresh token: ", err)
                  end
                end
              end
            end
          end

          log("logout session")
          local destroy_ok, destroy_err = session:logout()
          if not destroy_ok then
            return unexpected(client, tostring(destroy_err) or "unable to logout session")
          end
        end

        headers.no_cache()

        local end_session_endpoint = args.get_conf_arg("end_session_endpoint", oic.configuration.end_session_endpoint)
        if end_session_endpoint then
          local redirect_params_added = false
          if find(end_session_endpoint, "?", 1, true) then
            redirect_params_added = true
          end

          local u = { end_session_endpoint }
          local i = 1

          if id_token then
            u[i+1] = redirect_params_added and "&id_token_hint=" or "?id_token_hint="
            u[i+2] = id_token
            i=i+2
            redirect_params_added = true
          end

          if client.logout_redirect_uri then
            u[i+1] = redirect_params_added and "&post_logout_redirect_uri=" or "?post_logout_redirect_uri="
            u[i+2] = escape_uri(client.logout_redirect_uri)
          end

          log("redirecting to end session endpoint")
          return response.redirect(concat(u))

        else
          if client.logout_redirect_uri then
            log("redirecting to logout redirect uri")
            return response.redirect(client.logout_redirect_uri)
          end

          log("logout response")
          return response.success()
        end
      end
    end
  end

  -- find credentials
  local bearer_token
  local token_endpoint_args
  if not session_present then
    local hide_credentials = args.get_conf_arg("hide_credentials", false)

    if auth_methods.session then
      if session_error then
        log("session was not found (", session_error, ")")
      else
        log("session was not found")
      end
    end

    -- bearer token authentication
    if auth_methods.bearer
    or auth_methods.introspection
    or auth_methods.userinfo
    or auth_methods.kong_oauth2
    then
      log("trying to find bearer token")
      local bearer_token_param_type = args.get_param_types("bearer_token_param_type")
      for _, location in ipairs(bearer_token_param_type) do
        if location == "header" then
          bearer_token = args.get_header("authorization:bearer")
          if bearer_token then
            if hide_credentials then
              args.clear_header("Authorization")
            end
            break
          end

          bearer_token = args.get_header("access_token")
          if bearer_token then
            if hide_credentials then
              args.clear_header("access-token")
              args.clear_header("access_token")
            end
            break
          end

          bearer_token = args.get_header("x_access_token")
          if bearer_token then
            if hide_credentials then
              args.clear_header("x-access-token")
              args.clear_header("x_access_token")
            end
            break
          end
        elseif location == "cookie" then
          local name = args.get_conf_arg("bearer_token_cookie_name")
          if name then
            bearer_token = var["cookie_" .. name]
            if bearer_token then
              if hide_credentials then
                args.clear_cookie(name)
              end
              break
            end
          end

        elseif location == "query" then
          bearer_token = args.get_uri_arg("access_token")
          if bearer_token then
            if hide_credentials then
              args.clear_uri_arg("access_token")
            end
            break
          end

        elseif location == "body" then
          bearer_token = args.get_post_arg("access_token")
          if bearer_token then
            if hide_credentials then
              args.clear_post_arg("access_token")
            end
            break
          end

          bearer_token = args.get_json_arg("access_token")
          if bearer_token then
            if hide_credentials then
              args.clear_json_arg("access_token")
            end
            break
          end
        end
      end

      if bearer_token then
        log("found bearer token")
        session_data = {
          client = client.index,
          tokens = {
            access_token = bearer_token,
          },
        }

        -- additionally we can validate the id token as well
        -- and pass it on, if it is passed on the request
        local id_token_param_name = args.get_conf_arg("id_token_param_name")
        if id_token_param_name then
          log("trying to find id token")

          local id_token, loc = args.get_req_arg(
            id_token_param_name,
            args.get_param_types("id_token_param_type")
          )

          if id_token then
            log("found id token")
            if hide_credentials then
              if loc == "header" then
                args.clear_header(id_token_param_name, "X")

              elseif loc == "query" then
                args.clear_uri_arg(id_token_param_name)

              elseif loc == "post" then
                args.clear_post_arg(id_token_param_name)

              elseif loc == "json" then
                args.clear_json_arg(id_token_param_name)
              end
            end

            session_data.tokens.id_token = id_token

          else
            log("id token was not found")
          end
        end

      else
        log("bearer token was not found")
      end
    end

    if not bearer_token then
      if auth_methods.refresh_token then
        local refresh_token_param_name = args.get_conf_arg("refresh_token_param_name")
        if refresh_token_param_name then
          log("trying to find refresh token")

          local refresh_token, loc = args.get_req_arg(
            refresh_token_param_name,
            args.get_param_types("refresh_token_param_type")
          )

          if loc == "header" then
            local value_prefix = lower(sub(refresh_token, 1, 6))
            if value_prefix == "bearer" then
              refresh_token =  sub(refresh_token, 8)
            end
          end

          if refresh_token then
            log("found refresh token")
            if hide_credentials then
              log("hiding credentials from ", loc)
              if loc == "header" then
                args.clear_header(refresh_token_param_name, "X")

              elseif loc == "query" then
                args.clear_uri_arg(refresh_token_param_name)

              elseif loc == "post" then
                args.clear_post_arg(refresh_token_param_name)

              elseif loc == "json" then
                args.clear_json_arg(refresh_token_param_name)
              end
            end

            token_endpoint_args = {
              {
                refresh_token    = refresh_token,
                grant_type       = REFRESH_TOKEN_GRANT,
                ignore_signature = ignore_signature.refresh_token,
              },
            }
          else
            log("refresh token was not found")
          end
        end
      end

      if not token_endpoint_args then
        if auth_methods.password or auth_methods.client_credentials then
          local usr, pwd, loc1
          if auth_methods.password then
            log("trying to find credentials for password grant")
            usr, pwd, loc1 = args.get_credentials(PASSWORD_GRANT, "username",  "password")
          end

          local cid, sec, loc2, assertion, loc3
          if auth_methods.client_credentials then
            log("trying to find credentials for client credentials grant")
            cid, sec, loc2 = args.get_credentials(CLIENT_CREDENTIALS_GRANT, "client_id", "client_secret")
            if not cid or not sec then
              assertion, loc3 = args.get_credentials(JWT_BEARER_GRANT, "assertion")
            end
          end

          if usr and pwd and cid and sec then
            log("found credentials and will try both password and client credentials grants")

            token_endpoint_args = {
              {
                username         = usr,
                password         = pwd,
                grant_type       = PASSWORD_GRANT,
                ignore_signature = ignore_signature.password,
              },
              {
                client_id        = cid,
                client_secret    = sec,
                grant_type       = CLIENT_CREDENTIALS_GRANT,
                ignore_signature = ignore_signature.client_credentials,
              },
            }

          elseif usr and pwd and assertion then
            log("found credentials and will try both password and client credentials (via assertion) grants")

            token_endpoint_args = {
              {
                username         = usr,
                password         = pwd,
                grant_type       = PASSWORD_GRANT,
                ignore_signature = ignore_signature.password,
              },
              {
                assertion        = assertion,
                grant_type       = JWT_BEARER_GRANT,
                ignore_signature = ignore_signature.client_credentials,
              },
            }

          elseif usr and pwd then
            log("found credentials for password grant")

            token_endpoint_args = {
              {
                username         = usr,
                password         = pwd,
                grant_type       = PASSWORD_GRANT,
                ignore_signature = ignore_signature.password,
              },
            }

          elseif cid and sec then
            log("found credentials for client credentials grant")

            token_endpoint_args = {
              {
                client_id        = cid,
                client_secret    = sec,
                grant_type       = CLIENT_CREDENTIALS_GRANT,
                ignore_signature = ignore_signature.client_credentials,
              },
            }

          elseif assertion then
            log("found credentials via assertion for client credentials grant")

            token_endpoint_args = {
              {
                assertion        = assertion,
                grant_type       = JWT_BEARER_GRANT,
                ignore_signature = ignore_signature.client_credentials,
              },
            }
          else
            log("credentials for client credentials or password grants were not found")
          end

          if token_endpoint_args and hide_credentials then
            if loc1 == "header" or loc2 == "header" then
              args.clear_header("Authorization", "X")
              args.clear_header("Grant-Type",    "X")
              args.clear_header("Grant_Type",    "X")
            end

            if loc3 == "header" then
              args.clear_header("Assertion",  "X")
              args.clear_header("Grant-Type", "X")
            end

            if loc1 then
              if loc1 == "query" then
                args.clear_uri_arg("username", "password", "grant_type")

              elseif loc1 == "post" then
                args.clear_post_arg("username", "password", "grant_type")

              elseif loc1 == "json" then
                args.clear_json_arg("username", "password", "grant_type")
              end
            end

            if loc2 then
              if loc2 == "query" then
                args.clear_uri_arg("client_id", "client_secret", "grant_type")

              elseif loc2 == "post" then
                args.clear_post_arg("client_id", "client_secret", "grant_type")

              elseif loc2 == "json" then
                args.clear_json_arg("client_id", "client_secret", "grant_type")
              end
            end

            if loc3 then
              if loc3 == "query" then
                args.clear_uri_arg("assertion", "grant_type")

              elseif loc2 == "post" then
                args.clear_post_arg("assertion", "grant_type")

              elseif loc2 == "json" then
                args.clear_json_arg("assertion", "grant_type")
              end
            end
          end
        end
      end

      if type(token_endpoint_args) ~= "table" then
        -- authorization code flow
        if auth_methods.authorization_code then
          log("trying to open authorization code flow session")

          local authorization_secure = args.get_conf_arg("authorization_cookie_secure")
          if authorization_secure == nil then
            authorization_secure = kong.request.get_forwarded_scheme() == "https"
          end

          -- http_only can be configured via both parameters:
          -- authorization_cookie_http_only and authorization_cookie_httponly
          -- it defaults to true if not configured
          local http_only
          if args.get_conf_arg("authorization_cookie_http_only") == nil then
            http_only = args.get_conf_arg("authorization_cookie_httponly", true)
          else
            http_only = args.get_conf_arg("authorization_cookie_http_only")
          end

          local authorization, authorization_error, authorization_present = session_open({
            cookie_name      = args.get_conf_arg("authorization_cookie_name", "authorization"),
            rolling_timeout  = args.get_conf_arg("authorization_rolling_timeout")
                            or args.get_conf_arg("authorization_cookie_lifetime", 600),
            idling_timeout   = 0,
            absolute_timeout = 0,
            cookie_path      = args.get_conf_arg("authorization_cookie_path", "/"),
            cookie_domain    = args.get_conf_arg("authorization_cookie_domain"),
            cookie_same_site = args.get_conf_arg("authorization_cookie_same_site")
                            or args.get_conf_arg("authorization_cookie_samesite", "Default"),
            cookie_http_only = http_only,
            cookie_secure    = authorization_secure,
          })

          if authorization_present then
            log("found authorization code flow session")

            local authorization_data = authorization:get_data()
            if type(authorization_data) ~= "table" then
              authorization_data = {}
            end

            log("checking authorization code flow state")

            local state = authorization_data.state
            if state then
              log("found authorization code flow state")

              local nonce         = authorization_data.nonce
              local code_verifier = authorization_data.code_verifier

              clients.reset(authorization_data.client, client, oic, options)

              -- authorization code response
              token_endpoint_args = {
                state         = state,
                nonce         = nonce,
                code_verifier = code_verifier,
              }

              log("verifying authorization code flow")

              token_endpoint_args, err = oic.authorization:verify(token_endpoint_args)
              if type(token_endpoint_args) ~= "table" then
                log("invalid authorization code flow")

                headers.no_cache()

                if args.get_uri_arg("state") == state then
                  return unauthorized(err)

                elseif args.get_post_arg("state") == state then
                  return unauthorized(err)

                else
                  log(err)
                end

                authorization_data.args = get_authorization_args(args)

                log("creating authorization code flow request with previous parameters")
                token_endpoint_args, err = oic.authorization:request {
                  args          = authorization_data.args,
                  client        = client.index,
                  state         = state,
                  nonce         = nonce,
                  code_verifier = code_verifier,
                }

                if type(token_endpoint_args) ~= "table" then
                  log("unable to start authorization code flow request with previous parameters")
                  return unexpected(client, err)
                end

                log("starting a new authorization code flow with previous parameters")
                -- it seems that user may have opened a second tab
                -- lets redirect that to idp as well in case user
                -- had closed the previous, but with same parameters
                -- as before.
                authorization_data.uri = args.get_redirect_uri()
                if args.get_conf_arg("preserve_query_args") then
                  authorization_data.uri_args = var.args
                end
                authorization:set_data(authorization_data)
                local save_ok, save_err = authorization:save()
                if not save_ok then
                  return unexpected(client, tostring(save_err) or "unable to save authorization session cookie")
                end

                log("redirecting client to openid connect provider with previous parameters")
                return response.redirect(token_endpoint_args.url)
              end

              log("authorization code flow verified")

              dynamic_login_redirect_uri = authorization_data.uri

              if args.get_conf_arg("preserve_query_args") then
                dynamic_login_redirect_uri_args = authorization_data.uri_args
              end

              authorization:clear_request_cookie()
              local destroy_ok, destroy_err = authorization:destroy()
              if not destroy_ok then
                return unexpected(client, tostring(destroy_err) or "unable to destroy authorization session")
              end

              if var.request_method == "POST" then
                args.clear_post_arg("code", "state", "session_state")

              else
                args.clear_uri_arg("code", "state", "session_state")
              end

              token_endpoint_args.ignore_signature = ignore_signature.authorization_code
              token_endpoint_args = { token_endpoint_args }

            else
              log("authorization code flow state was not found")
            end

          else
            if authorization_error then
              log("authorization code flow session was not found (", authorization_error, ")")
            else
              log("authorization code flow session was not found")
            end
          end

          if type(token_endpoint_args) ~= "table" then
            log("creating authorization code flow request")

            headers.no_cache()

            local extra_args = get_authorization_args(args)

            token_endpoint_args, err = oic.authorization:request {
              args = extra_args,
            }

            if type(token_endpoint_args) ~= "table" then
              log("unable to start authorization code flow request")
              return unexpected(client, err)
            end

            local authorization_data = {
              uri           = args.get_redirect_uri(),
              args          = extra_args,
              client        = client.index,
              state         = token_endpoint_args.state,
              nonce         = token_endpoint_args.nonce,
              code_verifier = token_endpoint_args.code_verifier,
            }

            if args.get_conf_arg("preserve_query_args") then
              authorization_data.uri_args = var.args
            end

            authorization:set_data(authorization_data)

            local save_ok, save_err = authorization:save()
            if not save_ok then
              return unexpected(client, tostring(save_err) or "unable to save authorization session cookie")
            end

            log("redirecting client to openid connect provider")
            return response.redirect(token_endpoint_args.url)

          else
            log("authenticating using authorization code flow")
          end

        else
          return unauthorized("no suitable authorization credentials were provided")
        end
      end

    else
      log("authenticating using bearer token")
    end

  else
    log("authenticating using session")
  end

  if type(session_data) ~= "table" then
    session_data = {}
  end

  local credential, consumer

  local leeway = args.get_conf_arg("leeway", 0)
  local exp
  local ttl
  do
    local now = time()

    local ttl_default   = args.get_conf_arg("cache_ttl", 3600)
    local ttl_max       = args.get_conf_arg("cache_ttl_max")
    local ttl_min       = args.get_conf_arg("cache_ttl_min")
    local ttl_neg       = args.get_conf_arg("cache_ttl_neg")
    local ttl_resurrect = args.get_conf_arg("cache_ttl_resurrect")

    if ttl_max and ttl_max > 0 then
      if ttl_min and ttl_min > ttl_max then
        ttl_min = ttl_max
      end

      if ttl_default > ttl_max then
        ttl_default = ttl_max
      end
    end

    if ttl_min and ttl_min > 0 then
      if ttl_default < ttl_min then
        ttl_default = ttl_min
      end
    end

    ttl = {
      now = now,
      default_ttl = ttl_default,
      min_ttl = ttl_min,
      max_ttl = ttl_max,
      neg_ttl = ttl_neg,
      resurrect_ttl = ttl_resurrect
    }
  end

  local exp_default
  if ttl.default_ttl == 0 then
    exp_default = 0
  else
    exp_default = ttl.now + ttl.default_ttl
  end

  local tokens_encoded
  if type(session_data.tokens) == "table" then
    tokens_encoded = session_data.tokens
  end

  local tokens_decoded

  local auth_method = nil
  local introspection_data = nil
  local introspection_jwt = nil
  local introspected = false
  local userinfo_data = nil
  local userinfo_jwt = nil
  local userinfo_loaded = false
  local downstream_headers = nil

  local userinfo_load    = userinfo.new(args, oic, cache, ignore_signature.userinfo)
  local introspect_token = introspect.new(args, oic, cache, ignore_signature.introspection)

  -- retrieve or verify tokens
  if bearer_token then
    if auth_methods.bearer then
      log("verifying bearer token")
      tokens_decoded, err = oic.token:verify(tokens_encoded)
      if type(tokens_decoded) ~= "table" then
        if not auth_methods.introspection and
           not auth_methods.userinfo      and
           not auth_methods.kong_oauth2
        then
          log("unable to verify bearer token")
          return unauthorized(err or "invalid jwt token")
        end

        if err then
          log("unable to verify bearer token (", err, "), trying to introspect it")

        else
          log("unable to verify bearer token, trying to introspect it")
        end
      end
    end

    local introspection_check_active = args.get_conf_arg("introspection_check_active", true) ~= false

    if not auth_methods.bearer or type(tokens_decoded) ~= "table" or type(tokens_decoded.access_token) ~= "table" then
      if type(tokens_decoded) ~= "table" then
        tokens_decoded, err = oic.token:decode(tokens_encoded, TOKEN_DECODE_OPTS)
        if type(tokens_decoded) ~= "table" then
          return unauthorized(err)
        end
      end

      local access_token = type(tokens_encoded) == "table" and tokens_encoded.access_token
      if not access_token then
        return unauthorized("bearer token not found")
      end

      if type(tokens_decoded.access_token) == "table" then
        log("jwt bearer token was provided")
      else
        log("opaque bearer token was provided")
      end

      if auth_methods.kong_oauth2 then
        log("trying to find matching kong oauth2 token")
        introspection_data, err, credential, consumer = cache.kong_oauth2.load(ctx, access_token, ttl, true)
        introspected = true
        if type(introspection_data) == "table" then
          log("authenticated using kong oauth2")
          introspection_data.active = true
          auth_method = "kong_oauth2"

        elseif err then
          log("unable to authenticate with kong oauth2 (", err, ")")

        else
          log("unable to authenticate with kong oauth2")
        end
      end

      if type(introspection_data) ~= "table" then
        if auth_methods.introspection then
          log("trying to introspect bearer token")
          introspection_data, err, introspection_jwt = introspect_token(access_token, ttl)
          introspected = true
          if type(introspection_data) == "table" then
            if introspection_data.active == true then
              log("authenticated using introspection")
              auth_method = "introspection"

            elseif introspection_check_active then
              log("token is not active anymore")
            end

          elseif err then
            log("unable to authenticate using introspection (", err, ")")

          else
            log("unable to authenticate using introspection")
          end
        end
      end

      if type(introspection_data) ~= "table" then
        if auth_methods.userinfo then
          log("trying to validate token with user info endpoint")
          if type(userinfo_data) ~= "table" then
            userinfo_data, err, userinfo_jwt = userinfo_load(access_token, ttl, ignore_signature.userinfo)
            userinfo_loaded = true

            if type(userinfo_data) == "table" then
              log("authenticated using user info endpoint")
              introspection_data = { active = true }
              auth_method = "userinfo"

            elseif err then
              log("unable to authenticate using user info endpoint (", err, ")")

            else
              log("unable to authenticate using user info endpoint")
            end
          end
        end
      end

      if type(introspection_data) ~= "table" then
        log("authentication with bearer token failed")
        return unauthorized(err or "invalid introspection results")
      end

      if introspection_check_active and introspection_data.active ~= true then
        log("authentication with bearer token failed")
        return unauthorized(err or "inactive token")
      end

      exp = claims.exp(introspection_data, tokens_encoded, ttl.now, exp_default)

    else
      log("bearer token verified")

      if args.get_conf_arg("introspect_jwt_tokens", false) then
        log("introspecting jwt bearer token")
        introspection_data, err, introspection_jwt = introspect_token(tokens_encoded.access_token, ttl)
        introspected = true
        if type(introspection_data) == "table" then
          if introspection_data.active == true then
            log("jwt bearer token is active and not revoked")

          elseif introspection_check_active then
            return unauthorized("jwt bearer token is not active anymore or has been revoked")
          end

        else
          log("unable to introspect jwt bearer token")
          return unauthorized(err)
        end

        exp = claims.exp(introspection_data, tokens_encoded, ttl.now, exp_default)
      end

      if not exp then
        exp = claims.exp(tokens_decoded.access_token, tokens_encoded, ttl.now, exp_default)
      end

      log("authenticated using jwt bearer token")

      auth_method = "bearer"
    end

    if auth_methods.session then
      session_modified = true
      session:set_data({
        client  = client.index,
        tokens  = tokens_encoded,
        expires = exp,
      })
    end

  elseif type(tokens_encoded) ~= "table" then
    -- let's try to retrieve tokens when using authorization code flow,
    -- password credentials, client credentials or refresh_token
    local auth_params
    if type(token_endpoint_args) == "table" then
      for _, arg in ipairs(token_endpoint_args) do
        arg.args = args.get_conf_args("token_post_args_names", "token_post_args_values")
        arg.token_cache_key_include_scope = args.get_conf_arg("token_cache_key_include_scope", false)
        local client_args = args.get_conf_arg("token_post_args_client")
        if client_args then
          for _, client_arg_name in ipairs(client_args) do
            local extra_arg = args.get_uri_arg(client_arg_name)
            if extra_arg then
              if not arg.args then
                arg.args = {}
              end

              arg.args[client_arg_name] = extra_arg

            else
              extra_arg = args.get_post_arg(client_arg_name)
              if extra_arg then
                if not arg.args then
                  arg.args = {}
                end

                arg.args[client_arg_name] = extra_arg
              end
            end
          end
        end

        local token_headers = args.get_conf_args("token_headers_names", "token_headers_values")
        local token_headers_client = args.get_conf_arg("token_headers_client")
        if token_headers_client then
          log("parsing client headers for token request")
          for _, token_header_name in ipairs(token_headers_client) do
            local token_header_value = args.get_header(token_header_name)
            if token_header_value then
              if not token_headers then
                token_headers = {}
              end

              token_headers[token_header_name] = token_header_value
            end
          end
        end

        if token_headers then
          log("injecting token headers to token request")
          arg.headers = token_headers
        end

        local token_endpoint_auth_method = args.get_conf_arg("token_endpoint_auth_method")
        if token_endpoint_auth_method then
          arg.token_endpoint_auth_method = token_endpoint_auth_method
        end

        if args.get_conf_arg("cache_tokens") then
          local salt = args.get_conf_arg("cache_tokens_salt")

          log("trying to exchange credentials using token endpoint with caching enabled")
          tokens_encoded, err, downstream_headers = cache.tokens.load(oic, arg, ttl, true, false, salt)

          if type(tokens_encoded) == "table"            and
            (arg.grant_type == REFRESH_TOKEN_GRANT      or
             arg.grant_type == PASSWORD_GRANT           or
             arg.grant_type == CLIENT_CREDENTIALS_GRANT or
             arg.grant_type == JWT_BEARER_GRANT)
          then
            log("verifying tokens")
            tokens_decoded, err = oic.token:verify(tokens_encoded, arg)
            if type(tokens_decoded) ~= "table" then
              log("token verification failed, trying to exchange credentials ",
                  "using token endpoint with cache flushed")
              tokens_encoded, err, downstream_headers = cache.tokens.load(oic, arg, ttl, true, true, salt)

            else
              log("tokens verified")
            end
          end

        else
          log("trying to exchange credentials using token endpoint")
          tokens_encoded, err, downstream_headers = cache.tokens.load(oic, arg, ttl, false, false)
        end

        if type(tokens_encoded) == "table" then
          log("exchanged credentials with tokens")
          if arg.grant_type == JWT_BEARER_GRANT then
            auth_method = CLIENT_CREDENTIALS_GRANT
          else
            auth_method = arg.grant_type or "authorization_code"
          end

          auth_params = arg
          break
        end
      end
    end

    if type(tokens_encoded) ~= "table" then
      log("unable to exchange credentials with tokens")
      return unauthorized(err)
    end

    if type(tokens_decoded) ~= "table" then
      log("verifying tokens")
      tokens_decoded, err = oic.token:verify(tokens_encoded, auth_params)
      if type(tokens_decoded) ~= "table" then
        log("token verification failed")
        return unauthorized(err)

      else
        log("tokens verified")
      end
    end

    exp = claims.exp(tokens_decoded.access_token, tokens_encoded, ttl.now, exp_default)

    if auth_methods.session then
      session_modified = true
      session:set_data({
        client  = client.index,
        tokens  = tokens_encoded,
        expires = exp,
      })
    end

  elseif session_present then
    -- it looks like we are using session authentication
    log("authenticated using session")

    auth_method = "session"
    if session_data.expires then
      exp = session_data.expires
    else
      exp = exp_default
    end

  else
    return unauthorized("unable to authenticate with any enabled authentication method")
  end

  log("checking for access token")
  if type(tokens_encoded) ~= "table" or not tokens_encoded.access_token then
    return unauthorized("access token was not found")

  else
    log("found access token")
  end

  if not exp then
    exp = exp_default
  end

  local refresh_tokens = args.get_conf_arg("refresh_tokens", true)

  local leeway_adjusted_exp
  if exp ~= 0 and leeway ~= 0 then
    if refresh_tokens and tokens_encoded.refresh_token then
      leeway_adjusted_exp = exp - leeway
    else
      leeway_adjusted_exp = exp + leeway
    end

  else
    leeway_adjusted_exp = exp
  end

  if exp > 0 then
    local ttl_new = exp - ttl.now
    if ttl_new > 0 then
      if ttl.max_ttl and ttl.max_ttl > 0 then
        if ttl_new > ttl.max_ttl then
          ttl_new = ttl.max_ttl
        end
      end

      if ttl.min_ttl and ttl.min_ttl > 0 then
        if ttl_new < ttl.min_ttl then
          ttl_new = ttl.min_ttl
        end
      end

      ttl.default_ttl = ttl_new
    end
  end

  log("checking for access token expiration")

  if leeway_adjusted_exp == 0 or leeway_adjusted_exp > ttl.now then
    log("access token is valid and has not expired")

    if auth_method == "session" then
      if args.get_conf_arg("reverify") then
        log("reverifying tokens")
        if ignore_signature.session then
          tokens_decoded, err = oic.token:verify(tokens_encoded , { ignore_signature = true })
        else
          tokens_decoded, err = oic.token:verify(tokens_encoded)
        end

        if type(tokens_decoded) ~= "table" then
          log("reverifying tokens failed")
          return unauthorized(err)

        else
          log("reverified tokens")
        end
      end
    end

  else
    -- possibly expired

    if not refresh_tokens then
      return unauthorized("access token has expired and \
      refreshing of tokens was disabled", TOKEN_EXPIRED_MESSAGE, true)
    end

    if not tokens_encoded.refresh_token then
      return unauthorized("access token cannot be refreshed in \
      absence of refresh token", TOKEN_EXPIRED_MESSAGE, true)
    end

    log("trying to refresh access token using refresh token")

    local id_token = tokens_encoded.id_token
    local refresh_token = tokens_encoded.refresh_token

    local tokens_refreshed
    tokens_refreshed, err = oic.token:refresh(refresh_token)
    -- when leeway is configured we allow a refresh ahead of expiry. In case we have single-use
    -- refresh tokens and concurrent requests we can fail unjustified here.
    -- Allowing to skip refreshing and proxy when the token is still valid.
    -- https://konghq.atlassian.net/browse/FTI-2999

    -- the token is still valid (not expired),
    -- passing the expiry claimo(exp) and the current time according to ngx
    if not claims.token_is_expired(exp, ttl.now)
       -- and we encountered an error when refreshing tokens
       and (err or type(tokens_refreshed) ~= "table") then
      -- logging the error from the IDP
      if err then
        log("unable to refresh soon to be expiring access token using refresh token: ", err)
      end
      log("continuing request processing with non-expired access token despite the token refresh failure")
      proxy_despite_refresh_failure = true

    elseif type(tokens_refreshed) ~= "table" then
      log("unable to refresh access token using refresh token")
      return unauthorized(err)

    else
      log("refreshed access token using refresh token")
    end

    if not proxy_despite_refresh_failure then
      log("verifying refreshed tokens")
      if ignore_signature.refresh_token then
        tokens_decoded, err = oic.token:verify(tokens_refreshed, { ignore_signature = true })
      else
        tokens_decoded, err = oic.token:verify(tokens_refreshed)
      end

      if type(tokens_decoded) ~= "table" then
        log("unable to verify refreshed tokens")
        return unauthorized(err)

      else
        log("verified refreshed tokens")
      end

      local preserve_tokens
      if not tokens_refreshed.refresh_token then
        log("preserving refresh token")
        tokens_refreshed.refresh_token = refresh_token
        preserve_tokens = true
      end

      if not tokens_refreshed.id_token and id_token then
        log("preserving id token")
        tokens_refreshed.id_token = id_token
        preserve_tokens = true
      end

      if preserve_tokens then
        log("decoding tokens with preserved tokens")
        tokens_decoded, err = oic.token:decode(tokens_refreshed, TOKEN_DECODE_OPTS)
        if type(tokens_decoded) ~= "table" then
          log("unable to decode tokens with preserved tokens")
          return unauthorized(err)

        else
          log("decoded tokens with preserved tokens")
        end
      end

      tokens_encoded = tokens_refreshed

      exp = claims.exp(tokens_decoded.access_token, tokens_encoded, ttl.now, exp_default)

      if exp > 0 then
        local ttl_new = exp - ttl.now
        if ttl_new > 0 then
          if ttl.max_ttl and ttl.max_ttl > 0 then
            if ttl_new > ttl.max_ttl then
              ttl_new = ttl.max_ttl
            end
          end

          if ttl.min_ttl and ttl.min_ttl > 0 then
            if ttl_new < ttl.min_ttl then
              ttl_new = ttl.min_ttl
            end
          end

          ttl.default_ttl = ttl_new
        end
      end

      if auth_methods.session then
        if session_present then
          session_regenerate = true
        else
          session_modified = true
        end

        session:set_data({
          client  = client.index,
          tokens  = tokens_encoded,
          expires = exp,
        })
      end
    end
  end

  local decode_tokens = type(tokens_decoded) ~= "table"

  -- additional claims verification
  do
    -- additional non-standard verification of the claim against a jwt session cookie
    local jwt_session_cookie = args.get_conf_arg("jwt_session_cookie")
    if jwt_session_cookie then
      if decode_tokens and type(tokens_decoded) ~= "table" then
        decode_tokens = false
        tokens_decoded, err = oic.token:decode(tokens_encoded, TOKEN_DECODE_OPTS)
        if err then
          log("error decoding tokens (", err, ")")
        end
      end

      local jwt_session_claim = args.get_conf_arg("jwt_session_claim", "sid")
      if type(tokens_decoded) == "table" and type(tokens_decoded.access_token) == "table" then
        log("validating jwt claim against jwt session cookie")
        local jwt_session_cookie_value = args.get_value(var["cookie_" .. jwt_session_cookie])
        if not jwt_session_cookie_value then
          return unauthorized("jwt session cookie was not specified for session claim verification")
        end

        local jwt_session_claim_value

        jwt_session_claim_value = tokens_decoded.access_token.payload[jwt_session_claim]

        if not jwt_session_claim_value then

          return unauthorized("jwt session claim (" .. jwt_session_claim ..
          ") was not specified in jwt access token")
        end

        if jwt_session_claim_value ~= jwt_session_cookie_value then
          return unauthorized("invalid jwt session claim (" .. jwt_session_claim ..
                                       ") was specified in jwt access token")
        end

        log("jwt claim matches jwt session cookie")

      else
        log("jwt claim verification skipped as it was not found on access token")
      end
    end

    local check_required = function(name, required_name, claim_name, default)
      local requirements = args.get_conf_arg(required_name)
      if requirements then
        log("verifying required ", name)
        local claim_lookup
        if claim_name then
          claim_lookup = args.get_conf_arg(claim_name, default)
        else
          claim_lookup = default
        end

        if decode_tokens and type(tokens_decoded) ~= "table" then
          decode_tokens = false
          tokens_decoded, err = oic.token:decode(tokens_encoded, TOKEN_DECODE_OPTS)
          if err then
            log("error decoding tokens (", err, ")")
          end
        end

        if not introspected and type(tokens_decoded) == "table" and type(tokens_decoded.access_token) ~= "table" then
          log("introspecting token to verify required ", name)
          introspection_data, err, introspection_jwt = introspect_token(tokens_encoded.access_token, ttl)
          introspected = true
          if err then
            log("error introspecting token to verify required ", name, " (", err, ")")
          end
        end

        local access_token_values
        if type(introspection_data) == "table" then
          access_token_values = claims.find(introspection_data, claim_lookup)
          if access_token_values then
            log(name, " found in introspection results")
          else
            log(name, " not found in introspection results")
          end
        end

        if not access_token_values then
          if type(tokens_decoded) == "table" and type(tokens_decoded.access_token) == "table" then
            access_token_values = claims.find(tokens_decoded.access_token.payload, claim_lookup)
            if access_token_values then
              log(name, " found in access token")
            else
              log(name, " not found in access token")
            end
          end
        end

        if not access_token_values then
          return nil, name .. " required but no " .. name .. " found"
        end

        access_token_values = set.new(access_token_values)

        local has_valid_requirements
        for _, requirement in ipairs(requirements) do
          if set.has(requirement, access_token_values) then
            has_valid_requirements = true
            break
          end
        end

        if has_valid_requirements then
          log("required ", name, " were found")

        else
          return nil, "required " .. name .. " were not found [ " .. concat(access_token_values, ", ") .. " ]"
        end
      end

      return true
    end

    ok, err = check_required("issuers", "issuers_allowed", nil, { "iss" })
    if not ok then
      return unauthorized(err)
    end

    ok, err = check_required("scopes", "scopes_required", "scopes_claim", { "scope" })
    if not ok then
      return forbidden(err)
    end

    ok, err = check_required("audience", "audience_required", "audience_claim", { "aud" })
    if not ok then
      return forbidden(err)
    end

    ok, err = check_required("groups", "groups_required", "groups_claim", { "groups" })
    if not ok then
      return forbidden(err)
    end

    ok, err = check_required("roles", "roles_required", "roles_claim", { "roles" })
    if not ok then
      return forbidden(err)
    end
  end

  local search_userinfo = args.get_conf_arg("search_user_info")
  local by_username_ignore_case = args.get_conf_arg("by_username_ignore_case")

  -- consumer mapping
  if not consumer then
    local consumer_claim = args.get_conf_arg("consumer_claim")
    if consumer_claim then
      log("trying to find kong consumer")

      local consumer_by = args.get_conf_arg("consumer_by")

      if not consumer then
        if type(introspection_data) == "table" then
          log("trying to find consumer using introspection response")
          consumer, err = consumers.find(
            { payload = introspection_data }, consumer_claim, false, consumer_by, ttl, by_username_ignore_case)
          if consumer then
            log("consumer was found with introspection results")
          elseif err then
            log("consumer was not found with introspection results (", err, ")")
          else
            log("consumer was not found with introspection results")
          end
        end
      end

      if not consumer then
        if decode_tokens and type(tokens_decoded) ~= "table" then
          decode_tokens = false
          tokens_decoded, err = oic.token:decode(tokens_encoded, TOKEN_DECODE_OPTS)
          if err then
            log("error decoding tokens (", err, ")")
          end
        end

        if type(tokens_decoded) == "table" then
          if type(tokens_decoded.id_token) == "table" then
            log("trying to find consumer using id token")
            consumer, err = consumers.find(
              tokens_decoded.id_token, consumer_claim, false, consumer_by, ttl, by_username_ignore_case)
            if consumer then
              log("consumer was found with id token")
            elseif err then
              log("consumer was not found with id token (", err, ")")
            else
              log("consumer was not found with id token")
            end
          end

          if not consumer and type(tokens_decoded.access_token) == "table" then
            log("trying to find consumer using access token")
            consumer, err = consumers.find(
              tokens_decoded.access_token, consumer_claim, false, consumer_by, ttl, by_username_ignore_case)
            if consumer then
              log("consumer was found with access token")
            elseif err then
              log("consumer was not found with access token (", err, ")")
            else
              log("consumer was not found with access token")
            end
          end
        end
      end

      if not consumer and search_userinfo then
        if type(userinfo_data) ~= "table" and not userinfo_loaded then
          userinfo_data, err, userinfo_jwt = userinfo_load(tokens_encoded.access_token, ttl)
          userinfo_loaded = true

          if type(userinfo_data) == "table" then
            log("user info loaded")
          elseif err then
            log("user info could not be loaded (", err, ")")
          else
            log("user info could not be loaded")
          end
        end

        if type(userinfo_data) == "table" then
          log("trying to find consumer using user info")
          consumer, err = consumers.find(
            { payload = userinfo_data }, consumer_claim, false, consumer_by, ttl, by_username_ignore_case)
          if consumer then
            log("consumer was found with user info")
          elseif err then
            log("consumer was not found with user info (", err, ")")
          else
            log("consumer was not found with user info")
          end
        end
      end

      if not consumer then
        log("kong consumer was not found")

        local consumer_optional = args.get_conf_arg("consumer_optional", false)
        if consumer_optional then
          log("kong consumer is optional")

        else
          if err then
            return forbidden("kong consumer was not found (" .. err .. ")")
          else
            return forbidden("kong consumer was not found")
          end
        end

      else
        log("found kong consumer")
      end
    end
  end

  -- setting consumer context and headers
  consumers.set(ctx, consumer, credential)

  if not consumer then
    -- setting credential by arbitrary claim, in case when consumer mapping was not used
    local credential_claim = args.get_conf_arg("credential_claim")
    if credential_claim then
      log("finding credential claim value")

      local credential_value
      if type(introspection_data) == "table" then
        credential_value = claims.find(introspection_data, credential_claim)
        if credential_value then
          log("credential claim found in introspection results")
        else
          log("credential claim not found in introspection results")
        end
      end

      if not credential_value then
        if decode_tokens and type(tokens_decoded) ~= "table" then
          decode_tokens = false
          tokens_decoded, err = oic.token:decode(tokens_encoded, TOKEN_DECODE_OPTS)
          if err then
            log("error decoding tokens (", err, ")")
          end
        end

        if type(tokens_decoded) == "table" then
          if type(tokens_decoded.id_token) == "table" then
            credential_value = claims.find(tokens_decoded.id_token.payload, credential_claim)
            if credential_value then
              log("credential claim found in id token")
            else
              log("credential claim not found in id token")
            end
          end

          if not credential_value and type(tokens_decoded.access_token) == "table" then
            credential_value = claims.find(tokens_decoded.access_token.payload, credential_claim)
            if credential_value then
              log("credential claim found in access token")
            else
              log("credential claim not found in access token")
            end
          end
        end
      end

      if not credential_value and search_userinfo then
        if type(userinfo_data) ~= "table" and not userinfo_loaded then
          userinfo_data, err, userinfo_jwt = userinfo_load(tokens_encoded.access_token, ttl)
          userinfo_loaded = true

          if type(userinfo_data) == "table" then
            log("user info loaded")
          elseif err then
            log("user info could not be loaded (", err, ")")
          else
            log("user info could not be loaded")
          end
        end

        if type(userinfo_data) == "table" then
          log("trying to find credential using user info")
          credential_value = claims.find(userinfo_data, credential_claim)
          if credential_value then
            log("credential claim found in user info")
          else
            log("credential claim was not found in user info")
          end
        end
      end

      if not credential_value then
        log("credential claim was not found")

      elseif type(credential_value) == "table" then
        log("credential claim is invalid")

      else
        log("credential found '", credential_value, "'")
        ctx.authenticated_credential = {
          id = tostring(credential_value)
        }
      end
    end
  end

  -- trying to find authenticated groups for ACL plugin to filter
  local authenticated_groups_claim = args.get_conf_arg("authenticated_groups_claim")
  if authenticated_groups_claim then
    log("finding authenticated groups claim value")

    local authenticated_groups
    if type(introspection_data) == "table" then
      authenticated_groups = claims.find(introspection_data, authenticated_groups_claim, true)
      if authenticated_groups then
        log("authenticated groups claim found in introspection results")
      else
        log("authenticated groups claim not found in introspection results")
      end
    end

    if not authenticated_groups then
      if decode_tokens and type(tokens_decoded) ~= "table" then
        decode_tokens = false
        tokens_decoded, err = oic.token:decode(tokens_encoded, TOKEN_DECODE_OPTS)
        if err then
          log("error decoding tokens (", err, ")")
        end
      end

      if type(tokens_decoded) == "table" then
        if type(tokens_decoded.id_token) == "table" then
          authenticated_groups = claims.find(tokens_decoded.id_token.payload, authenticated_groups_claim, true)
          if authenticated_groups then
            log("authenticated groups found in id token")
          else
            log("authenticated groups not found in id token")
          end
        end

        if not authenticated_groups and type(tokens_decoded.access_token) == "table" then
          authenticated_groups = claims.find(tokens_decoded.access_token.payload, authenticated_groups_claim, true)
          if authenticated_groups then
            log("authenticated groups claim found in access token")
          else
            log("authenticated groups claim not found in access token")
          end
        end
      end
    end

    if not authenticated_groups and search_userinfo then
      if type(userinfo_data) ~= "table" and not userinfo_loaded then
        userinfo_data, err, userinfo_jwt = userinfo_load(tokens_encoded.access_token, ttl)
        userinfo_loaded = true

        if type(userinfo_data) == "table" then
          log("user info loaded")
        elseif err then
          log("user info could not be loaded (", err, ")")
        else
          log("user info could not be loaded")
        end
      end

      if type(userinfo_data) == "table" then
        log("trying to find credential using user info")
        authenticated_groups = claims.find(userinfo_data, authenticated_groups_claim, true)
        if authenticated_groups then
          log("authenticated groups claim found in user info")
        else
          log("authenticated groups claim was not found in user info")
        end
      end
    end

    if not authenticated_groups then
      log("authenticated groups claim was not found")
    else
      log("authenticated groups found '", inspect(authenticated_groups), "'")
      local groups = set.new(authenticated_groups)
      ctx.authenticated_groups = groups
      headers.set_upstream("X-Authenticated-Groups", concat(groups, ", "))
    end
  end

  -- here we replay token endpoint request response headers, if any
  headers.replay_downstream(args, downstream_headers, auth_method)

  -- proprietary token exchange
  local token_exchanged
  do
    local exchange_token_endpoint = args.get_conf_arg("token_exchange_endpoint")
    if exchange_token_endpoint then
      local error_status
      local opts = args.get_http_opts({
        method  = "POST",
        headers = {
          Authorization = "Bearer " .. tokens_encoded.access_token,
        },
      })

      if args.get_conf_arg("cache_token_exchange") then
        log("trying to exchange access token with caching enabled")
        token_exchanged, err, error_status = cache.token_exchange.load(
          tokens_encoded.access_token, exchange_token_endpoint, opts, ttl, true)

      else
        log("trying to exchange access token")
        token_exchanged, err, error_status = cache.token_exchange.load(
          tokens_encoded.access_token, exchange_token_endpoint, opts, ttl, false)
      end

      if not token_exchanged or error_status ~= 200 then
        if error_status == 401 then
          return unauthorized(err or "exchange token endpoint returned unauthorized")

        elseif error_status == 403 then
          return forbidden(err or "exchange token endpoint returned forbidden")

        else
          if err then
            return unexpected(client, err)
          else
            return unexpected(client, "exchange token endpoint returned ", error_status or "unknown")
          end
        end

      else
        log("exchanged access token successfully")
      end
    end
  end

  log("setting upstream and downstream headers")
  local downstream_headers_claims = args.get_conf_arg("downstream_headers_claims")
  local downstream_headers_names  = args.get_conf_arg("downstream_headers_names")
  do
    local upstream_headers_claims = args.get_conf_arg("upstream_headers_claims")
    local upstream_headers_names  = args.get_conf_arg("upstream_headers_names")
    if upstream_headers_claims and upstream_headers_names then
      for i, claim in ipairs(upstream_headers_claims) do
        claim = args.get_value(claim)
        if claim then
          local name = args.get_value(upstream_headers_names[i])
          if name then
            local value
            if type(introspection_data) == "table" then
              value = headers.get(args.get_value(introspection_data[claim]))
            end

            if not value and type(tokens_encoded) == "table" then
              if decode_tokens and type(tokens_decoded) ~= "table" then
                decode_tokens = false
                tokens_decoded, err = oic.token:decode(tokens_encoded, TOKEN_DECODE_OPTS)
                if err then
                  log("error decoding tokens (", err, ")")
                end
              end

              if type(tokens_decoded) == "table" then
                if type(tokens_decoded.access_token) == "table" then
                  value = headers.get(args.get_value(tokens_decoded.access_token.payload[claim]))
                end

                if not value and type(tokens_decoded.id_token) == "table" then
                  value = headers.get(args.get_value(tokens_decoded.id_token.payload[claim]))
                end
              end
            end

            if not value and search_userinfo then
              if type(userinfo_data) ~= "table" and not userinfo_loaded then
                userinfo_data, err, userinfo_jwt = userinfo_load(tokens_encoded.access_token, ttl)
                userinfo_loaded = true

                if userinfo_data then
                  log("user info loaded")
                elseif err then
                  log("user info could not be loaded (", err, ")")
                else
                  log("user info could not be loaded")
                end
              end

              if type(userinfo_data) == "table" then
                value = headers.get(args.get_value(userinfo_data[claim]))
              end
            end

            if value then
              headers.set_upstream(name, value)
            end
          end
        end
      end
    end

    if downstream_headers_claims and downstream_headers_names then
      for i, claim in ipairs(downstream_headers_claims) do
        claim = args.get_value(claim)
        if claim then
          local name = args.get_value(downstream_headers_names[i])
          if name then
            local value
            if type(introspection_data) == "table" then
              value = headers.get(args.get_value(introspection_data[claim]))
            end

            if not value and type(tokens_encoded) == "table" then
              if decode_tokens and type(tokens_decoded) ~= "table" then
                decode_tokens = false
                tokens_decoded, err = oic.token:decode(tokens_encoded, TOKEN_DECODE_OPTS)
                if err then
                  log("error decoding tokens (", err, ")")
                end
              end

              if type(tokens_decoded) == "table" then
                if type(tokens_decoded.access_token) == "table" then
                  value = headers.get(args.get_value(tokens_decoded.access_token.payload[claim]))
                end

                if not value and type(tokens_decoded.id_token) == "table" then
                  value = headers.get(args.get_value(tokens_decoded.id_token.payload[claim]))
                end
              end
            end

            if not value and search_userinfo then
              if type(userinfo_data) ~= "table" and not userinfo_loaded then
                userinfo_data, err, userinfo_jwt = userinfo_load(tokens_encoded.access_token, ttl)
                userinfo_loaded = true

                if type(userinfo_data) == "table" then
                  log("user info loaded")
                elseif err then
                  log("user info could not be loaded (", err, ")")
                else
                  log("user info could not be loaded")
                end
              end

              if type(userinfo_data) == "table" then
                value = headers.get(args.get_value(userinfo_data[claim]))
              end
            end

            if value then
              headers.set_downstream(name, value)
            end
          end
        end
      end
    end

    -- full headers
    headers.set(args, "access_token",  token_exchanged or tokens_encoded.access_token)
    headers.set(args, "id_token",      tokens_encoded.id_token)
    headers.set(args, "refresh_token", tokens_encoded.refresh_token)
    headers.set(args, "introspection", introspection_data or function()
      if not introspected then
        introspection_data, err, introspection_jwt = introspect_token(tokens_encoded.access_token, ttl)
        introspected = true
        if err then
          log("error introspecting token (", err, ")")
        end
      end
      return introspection_data
    end)

    headers.set(args, "introspection_jwt", introspection_jwt or function()
      if not introspected then
        introspection_data, err, introspection_jwt = introspect_token(tokens_encoded.access_token, ttl)
        introspected = true
        if err then
          log("error introspecting token (", err, ")")
        end
      end
      return introspection_jwt
    end)

    headers.set(args, "user_info", userinfo_data or function()
      if not userinfo_loaded then
        userinfo_data, err, userinfo_jwt = userinfo_load(tokens_encoded.access_token, ttl)
        if err then
          log("error loading userinfo (", err, ")")
        end
        userinfo_loaded = true
      end
      return userinfo_data
    end)

    headers.set(args, "user_info_jwt", userinfo_jwt or function()
      if not userinfo_loaded then
        userinfo_data, err, userinfo_jwt = userinfo_load(tokens_encoded.access_token, ttl)
        if err then
          log("error loading userinfo (", err, ")")
        end
        userinfo_loaded = true
      end
      return userinfo_jwt
    end)

    headers.set(args, "access_token_jwk", function()
      if decode_tokens and type(tokens_decoded) ~= "table" then
        decode_tokens = false
        tokens_decoded, err = oic.token:decode(tokens_encoded, TOKEN_DECODE_OPTS)
        if err then
          log("error decoding tokens (", err, ")")
        end
      end

      if type(tokens_decoded) == "table" then
        local access_token = tokens_decoded.access_token
        if type(access_token) == "table" and access_token.jwk then
          return access_token.jwk
        end
      end
    end)

    headers.set(args, "id_token_jwk", function()
      if decode_tokens and type(tokens_decoded) ~= "table" then
        decode_tokens = false
        tokens_decoded, err = oic.token:decode(tokens_encoded, TOKEN_DECODE_OPTS)
        if err then
          log("error decoding tokens (", err, ")")
        end
      end

      if type(tokens_decoded) == "table" then
        local id_token = tokens_decoded.id_token
        if type(id_token) == "table" and id_token.jwk then
          return id_token.jwk
        end
      end
    end)
  end

  if auth_methods.session then
    if session_present then
      log("hiding session cookie from upstream")
      session:clear_request_cookie()
    end

    if session_regenerate or session_modified or session_present then
      local skip_session
      local disable_session = args.get_conf_arg("disable_session")
      if disable_session then
        for _, session_auth_method in ipairs(disable_session) do
          if session_auth_method == auth_method then
            skip_session = true
            break
          end
        end
      end

      if not skip_session and (not proxy_despite_refresh_failure) then
        if session_regenerate or session_modified then
          log("saving session")
          local subject
          local authenticated_consumer = ctx.authenticated_consumer
          if authenticated_consumer then
            if authenticated_consumer.username then
              subject = authenticated_consumer.username
            elseif authenticated_consumer.custom_id then
              subject = authenticated_consumer.custom_id
            else
              subject = authenticated_consumer.id
            end
          end

          if not subject and ctx.authenticated_credential then
            subject = ctx.authenticated_credential.id
          end

          if subject then
            session:set_subject(subject)
          end

          local save_ok, save_err = session:save()
          if not save_ok then
            return unexpected(client, tostring(save_err) or "unable to save session cookie")
          end

        elseif session_present then
          log("refreshing session")
          local refresh_ok, refresh_err = session:refresh()
          if not refresh_ok then
            return unexpected(client, tostring(refresh_err) or "unable to refresh session")
          end
        end

        session:set_headers()

        if downstream_headers_claims and downstream_headers_names then
          headers.set(args, "session_id", function()
            return session:get_property("id")
          end)
        end
      end
    end
  end

  -- login actions
  do
    local login_action = args.get_conf_arg("login_action")
    if login_action == "response" or login_action == "redirect" then
      local has_login_method

      local login_methods = args.get_conf_arg("login_methods", { "authorization_code" })
      for _, login_method in ipairs(login_methods) do
        if auth_method == login_method then
          has_login_method = true
          break
        end
      end

      if has_login_method then
        if login_action == "response" then
          local login_response = {}

          local login_tokens = args.get_conf_arg("login_tokens")
          if login_tokens then
            log("adding login tokens to response")
            local output_tokens
            local output_introspection
            for _, name in ipairs(login_tokens) do
              if name == "tokens" then
                output_tokens = true
                break
              elseif name == "introspection" then
                output_introspection = true
              end
            end

            local response_tokens
            if output_introspection then
              if introspection_data then
                response_tokens = introspection_data
              elseif output_tokens then
                response_tokens = tokens_encoded
              end

            elseif output_tokens then
              response_tokens = tokens_encoded
            end

            if response_tokens then
              login_response = response_tokens

            elseif tokens_encoded then
              for _, name in ipairs(login_tokens) do
                if tokens_encoded[name] then
                  login_response[name] = tokens_encoded[name]
                end
              end
            end
          end

          log("login with response login action")
          return response.success(args.get_value(login_response))

        elseif login_action == "redirect" then
          local login_redirect_uri = client.login_redirect_uri or
            dynamic_login_redirect_uri

          if login_redirect_uri then
            local query
            local fragment

            local fragment_start = find(login_redirect_uri, "#", 1, true)
            if fragment_start then
              fragment = sub(login_redirect_uri, fragment_start)
              login_redirect_uri = sub(login_redirect_uri, 1, fragment_start - 1)
            end

            local query_start = find(login_redirect_uri, "?", 1, true)
            if query_start then
              query = gsub(sub(login_redirect_uri, query_start), "&+$", "")
              login_redirect_uri = sub(login_redirect_uri, 1, query_start - 1)
            end

            if dynamic_login_redirect_uri_args then
              if query then
                query = gsub(concat({ query, dynamic_login_redirect_uri_args }, "&"), "&+$", "")
              else
                query = "?" ..  gsub(dynamic_login_redirect_uri_args, "&+$", "")
              end
            end

            local login_tokens = args.get_conf_arg("login_tokens")
            if login_tokens then
              log("adding login tokens to redirect uri")

              local login_token_argc = 0
              local login_token_args

              for _, name in ipairs(login_tokens) do
                local value
                if name == "tokens" then
                  value = tokens_encoded

                elseif name == "introspection" then
                  if introspection_data then
                    value = introspection_data
                  end

                else
                  value = tokens_encoded[name]
                end

                if value then
                  if type(value) == "table" then
                    value = json.encode(value)
                    if value then
                      value = base64url.encode(value)
                    end

                  else
                    value = tostring(value)
                  end

                  if not login_token_args then
                    login_token_args = {}
                  end

                  login_token_args[login_token_argc + 1] = name
                  login_token_args[login_token_argc + 2] = "="
                  login_token_args[login_token_argc + 3] = value
                  login_token_args[login_token_argc + 4] = "&"
                  login_token_argc = login_token_argc + 4
                end
              end

              if login_token_argc > 0 then
                login_token_args = concat(login_token_args, nil, 1, login_token_argc - 1)
                local login_redirect_mode = args.get_conf_arg("login_redirect_mode", "fragment")
                if login_redirect_mode == "query" then
                  if query then
                    query =  gsub(concat({ query, login_token_args }, "&"), "&+$", "")
                  else
                    query = "?" .. gsub(login_token_args, "&+$", "")
                  end

                else
                  if fragment then
                    fragment = gsub(concat({ fragment, login_token_args }, "&"), "&+$", "")
                  else
                    fragment = "#" .. gsub(login_token_args, "&+$", "")
                  end
                end
              end
            end

            if query then
              login_redirect_uri = login_redirect_uri .. query
            end

            if fragment then
              login_redirect_uri = login_redirect_uri .. fragment
            end

            headers.no_cache()

            log("login with redirect login action")
            return response.redirect(login_redirect_uri)

          else
            log.notice("login action was set to redirect but no login redirect uri was specified")
          end
        end
      end
    end
  end

  if dynamic_login_redirect_uri_args then
    log("preserving uri args")
    args.set_uri_args(dynamic_login_redirect_uri_args)
  end

  log("proxying to upstream")
end


return OICHandler
