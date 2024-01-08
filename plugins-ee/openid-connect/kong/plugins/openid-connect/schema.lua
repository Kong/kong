-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]


local Schema = require "kong.db.schema"


local typedefs          = require "kong.db.schema.typedefs"
local table_contains    = require "kong.tools.utils".table_contains
local oidcdefs          = require "kong.plugins.openid-connect.typedefs"
local cache             = require "kong.plugins.openid-connect.cache"
local arguments         = require "kong.plugins.openid-connect.arguments"


local get_phase = ngx.get_phase


local function validate_issuer(conf)
  local phase = get_phase()
  if phase ~= "access" and phase ~= "content" then
    return true
  end

  local args = arguments(conf)

  local issuer_uri = args.get_conf_arg("issuer")
  if not issuer_uri then
    return true
  end

  local options = args.get_http_opts({
    extra_jwks_uris = args.get_conf_arg("extra_jwks_uris"),
    headers         = args.get_conf_args("discovery_headers_names", "discovery_headers_values"),
  })

  local keys = cache.issuers.rediscover(issuer_uri, options)
  if not keys then
    return false, "openid connect discovery failed"
  end

  return true
end

local function check_auth_method_for_mtls_pop(conf)
  if not conf.proof_of_possession_auth_methods_validation then
    return true
  end

  -- default auth method contain other auth methods
  if not conf.auth_methods then
    return false
  end

  for _, auth_method in ipairs(conf.auth_methods) do
    if auth_method ~= "bearer" and auth_method ~= "introspection" and auth_method ~= "session" then
      return false
    end
  end

  return true
end


local function validate_proof_of_possession(conf)
  local self_signed_verify_support = kong.configuration.loaded_plugins["tls-handshake-modifier"]
  local ca_chain_verify_support = kong.configuration.loaded_plugins["mtls-auth"]

  if conf.proof_of_possession_mtls == "strict" or conf.proof_of_possession_mtls == "optional" then
    if not (self_signed_verify_support or ca_chain_verify_support) then
      return false, "mTLS-proof-of-possession requires client certificate authentication. " ..
        "'tls-handshake-modifier' or 'mtls-auth' plugin could be used for this purpose."
    end

    if not check_auth_method_for_mtls_pop(conf) then
      return false, "mTLS-proof-of-possession only supports 'bearer', 'introspection', 'session' auth methods when proof_of_possession_auth_methods_validation is set to true."
    end
  end

  return true
end


local function validate_tls_client_auth_certs(conf)
  local client_auth = conf.client_auth
  client_auth = type(client_auth) == "table" and client_auth or {}

  local function has_auth_method(value)
    return table_contains(client_auth, value)                or
           conf.token_endpoint_auth_method         == value  or
           conf.introspection_endpoint_auth_method == value  or
           conf.revocation_endpoint_auth_method    == value
  end

  local tls_client_auth_enabled = has_auth_method("tls_client_auth") or
                                  has_auth_method("self_signed_tls_client_auth")
  if not tls_client_auth_enabled then
    return true
  end

  local tls_client_auth_cert_id = conf.tls_client_auth_cert_id ~= ngx.null and conf.tls_client_auth_cert_id
  if not tls_client_auth_cert_id then
    return false, "tls_client_auth_cert_id is required when tls client auth is enabled"
  end
  return true
end


local function validate(conf)
  local ok, err = validate_issuer(conf)
  if not ok then
    return false, err
  end

  ok, err = validate_tls_client_auth_certs(conf)
  if not ok then
    return false, err
  end

  return validate_proof_of_possession(conf)
end


local session_headers = Schema.define({
  type = "set",
  elements = {
    type = "string",
    one_of = {
      "id",
      "audience",
      "subject",
      "timeout",
      "idling-timeout",
      "rolling-timeout",
      "absolute-timeout",
    },
  },
})


local config = {
  name = "openid-connect",
  fields = {
    { consumer  = typedefs.no_consumer    },
    { protocols = typedefs.protocols_http },
    { consumer_group = typedefs.no_consumer_group },
    { config    = {
        type             = "record",
        custom_validator = validate,
        fields           = {
          {
            issuer = typedefs.url {
              required = true,
            },
          },
          {
            discovery_headers_names = { description = "Extra header names passed to the discovery endpoint.", required = false,
              type     = "array",
              elements = {
                type   = "string",
              },
            },
          },
          {
            discovery_headers_values = { description = "Extra header values passed to the discovery endpoint.", required = false,
              type     = "array",
              elements = {
                type   = "string",
              },
            },
          },
          {
            extra_jwks_uris = { description = "JWKS URIs whose public keys are trusted (in addition to the keys found with the discovery).", required = false,
              type     = "set",
              elements = typedefs.url,
            },
          },
          {
            rediscovery_lifetime = { description = "Specifies how long (in seconds) the plugin waits between discovery attempts. Discovery is still triggered on an as-needed basis.", required = false,
              type     = "number",
              default  = 30,
            },
          },
          {
            auth_methods = { description = "Types of credentials/grants to enable.", required = false,
              type     = "array",
              default  = {
                "password",
                "client_credentials",
                "authorization_code",
                "bearer",
                "introspection",
                "userinfo",
                "kong_oauth2",
                "refresh_token",
                "session",
              },
              elements = {
                type   = "string",
                one_of = {
                  "password",
                  "client_credentials",
                  "authorization_code",
                  "bearer",
                  "introspection",
                  "userinfo",
                  "kong_oauth2",
                  "refresh_token",
                  "session",
                },
              },
            },
          },
          {
            client_id = { description = "The client id(s) that the plugin uses when it calls authenticated endpoints on the identity provider.", required  = false,
              type      = "array",
              encrypted = true,
              elements  = {
                type    = "string",
                referenceable = true,
              },
            },
          },
          {
            client_secret = { description = "The client secret.", required  = false,
              type      = "array",
              encrypted = true,
              elements  = {
                type    = "string",
                referenceable = true,
              },
            },
          },
          {
            client_auth = { description = "The authentication method used by the client (plugin) when calling the endpoint.", required  = false,
              type      = "array",
              elements  = {
                type    = "string",
                one_of  = {
                  "client_secret_basic",
                  "client_secret_post",
                  "client_secret_jwt",
                  "private_key_jwt",
                  "tls_client_auth",
                  "self_signed_tls_client_auth",
                  "none",
                },
              },
            },
          },
          {
            client_jwk  = {
              required  = false,
              type      = "array",
              elements  = oidcdefs.jwk,
            },
          },
          {
            client_alg  = {
              required  = false,
              type      = "array",
              elements  = {
                type    = "string",
                one_of = {
                  "HS256",
                  "HS384",
                  "HS512",
                  "RS256",
                  "RS384",
                  "RS512",
                  "ES256",
                  "ES384",
                  "ES512",
                  "PS256",
                  "PS384",
                  "PS512",
                  "EdDSA",
                },
              },
            },
          },
          {
            client_arg = { description = "The client to use for this request (the selection is made with a request parameter with the same name).", required = false,
              type     = "string",
              default  = "client_id",
            },
          },
          {
            redirect_uri = { description = "The redirect URI passed to the authorization and token endpoints.", required = false,
              type     = "array",
              elements = typedefs.url,
            },
          },
          {
            login_redirect_uri = { description = "Where to redirect the client when `login_action` is set to `redirect`.", required = false,
              type     = "array",
              elements = typedefs.url { referenceable = true },
            },
          },
          {
            logout_redirect_uri = { description = "Where to redirect the client after the logout.", required = false,
              type     = "array",
              elements = typedefs.url { referenceable = true },
            },
          },
          {
            forbidden_redirect_uri = { description = "Where to redirect the client on forbidden requests.", required = false,
              type     = "array",
              elements = typedefs.url,
            },
          },
          {
            forbidden_error_message = { description = "The error message for the forbidden requests (when not using the redirection).", required = false,
              type     = "string",
              default  = "Forbidden",
            },
          },
          {
            forbidden_destroy_session = { description = "Destroy any active session for the forbidden requests.", required = false,
              type     = "boolean",
              default  = true,
            },
          },
          {
            unauthorized_destroy_session = { description = "Destroy any active session for the unauthorized requests.", required = false,
            type     = "boolean",
            default  = true,
            },
          },
          {
            unauthorized_redirect_uri = { description = "Where to redirect the client on unauthorized requests.", required = false,
              type     = "array",
              elements = typedefs.url,
            },
          },
          {
            unauthorized_error_message = { description = "The error message for the unauthorized requests (when not using the redirection).", required = false,
              type     = "string",
              default  = "Unauthorized",
            },
          },
          {
            unexpected_redirect_uri = { description = "Where to redirect the client when unexpected errors happen with the requests.", required = false,
              type     = "array",
              elements = typedefs.url,
            },
          },
          {
            response_mode = { description = "The response mode passed to the authorization endpoint: - `query`: Instructs the identity provider to pass parameters in query string - `form_post`: Instructs the identity provider to pass parameters in request body - `fragment`: Instructs the identity provider to pass parameters in uri fragment (rarely useful as the plugin itself cannot read it)", required = false,
              type     = "string",
              default  = "query",
              one_of   = {
                "query",
                "form_post",
                "fragment",
              },
            },
          },
          {
            response_type = { description = "The response type passed to the authorization endpoint.", required = false,
              type     = "array",
              default  = {
                "code",
              },
              elements = {
                type = "string",
              },
            },
          },
          {
            scopes = { description = "The scopes passed to the authorization and token endpoints.", required = false,
              type     = "array",
              default  = {
                "openid",
              },
              elements = {
                type = "string",
                referenceable = true,
              },
            },
          },
          {
            audience = { description = "The audience passed to the authorization endpoint.", required = false,
              type     = "array",
              elements = {
                type = "string",
              },
            },
          },
          {
            issuers_allowed = { description = "The issuers allowed to be present in the tokens (`iss` claim).", required = false,
              type     = "array",
              elements = {
                type = "string",
              },
            },
          },
          {
            scopes_required = { description = "The scopes (`scopes_claim` claim) required to be present in the access token (or introspection results) for successful authorization. This config parameter works in both **AND** / **OR** cases.",
              required = false,
              type     = "array",
              elements = {
                type = "string",
              },
            },
          },
          {
            scopes_claim = { description = "The claim that contains the scopes. If multiple values are set, it means the claim is inside a nested object of the token payload.", required = false,
              type     = "array",
              default  = { "scope" },
              elements = {
                type = "string",
              },
            },
          },
          {
            audience_required = { description = "The audiences (`audience_claim` claim) required to be present in the access token (or introspection results) for successful authorization. This config parameter works in both **AND** / **OR** cases.",
              required = false,
              type     = "array",
              elements = {
                type = "string",
              },
            },
          },
          {
            audience_claim = { description = "The claim that contains the audience. If multiple values are set, it means the claim is inside a nested object of the token payload.", required = false,
              type     = "array",
              default  = { "aud" },
              elements = {
                type = "string",
              },
            },
          },
          {
            groups_required = { description = "The groups (`groups_claim` claim) required to be present in the access token (or introspection results) for successful authorization. This config parameter works in both **AND** / **OR** cases.",
              required = false,
              type     = "array",
              elements = {
                type = "string",
              },
            },
          },
          {
            groups_claim = { description = "The claim that contains the groups. If multiple values are set, it means the claim is inside a nested object of the token payload.", required = false,
              type     = "array",
              default  = { "groups" },
              elements = {
                type = "string",
              },
            },
          },
          {
            roles_required = { description = "The roles (`roles_claim` claim) required to be present in the access token (or introspection results) for successful authorization. This config parameter works in both **AND** / **OR** cases.",
              required = false,
              type     = "array",
              elements = {
                type = "string",
              },
            },
          },
          {
            roles_claim = { description = "The claim that contains the roles. If multiple values are set, it means the claim is inside a nested object of the token payload.", required = false,
              type     = "array",
              default  = { "roles" },
              elements = {
                type = "string",
              },
            },
          },
          {
            domains = { description = "The allowed values for the `hd` claim.", required = false,
              type     = "array",
              elements = {
                type = "string",
              },
            },
          },
          {
            max_age = { description = "The maximum age (in seconds) compared to the `auth_time` claim.", required = false,
              type     = "number",
            },
          },
          {
            authenticated_groups_claim = { description = "The claim that contains authenticated groups. This setting can be used together with ACL plugin, but it also enables IdP managed groups with other applications and integrations. If multiple values are set, it means the claim is inside a nested object of the token payload.", required = false,
              type     = "array",
              elements = {
                type = "string",
              },
            },
          },
          {
            authorization_endpoint = typedefs.url {
              required = false,
            },
          },
          {
            authorization_query_args_names = { description = "Extra query argument names passed to the authorization endpoint.", required = false,
              type     = "array",
              elements = {
                type   = "string",
              },
            },
          },
          {
            authorization_query_args_values = { description = "Extra query argument values passed to the authorization endpoint.", required = false,
              type     = "array",
              elements = {
                type   = "string",
              },
            },
          },
          {
            authorization_query_args_client = { description = "Extra query arguments passed from the client to the authorization endpoint.", required = false,
              type     = "array",
              elements = {
                type   = "string",
              },
            },
          },
          {
            authorization_rolling_timeout = { description = "Specifies how long the session used for the authorization code flow can be used in seconds until it needs to be renewed. 0 disables the checks and rolling.", required = false,
              type     = "number",
              default  = 600,
            },
          },
          {
            authorization_cookie_name = { description = "The authorization cookie name.", required = false,
              type     = "string",
              default  = "authorization",
            },
          },
          {
            authorization_cookie_path = typedefs.path {
              required = false,
              default  = "/",
            },
          },
          {
            authorization_cookie_domain = { description = "The authorization cookie Domain flag.", required = false,
              type     = "string",
            },
          },
          {
            authorization_cookie_same_site = { description = "Controls whether a cookie is sent with cross-origin requests, providing some protection against cross-site request forgery attacks.", required = false,
              type     = "string",
              default  = "Default",
              one_of   = {
                "Strict",
                "Lax",
                "None",
                "Default",
              },
            },
          },
          {
            authorization_cookie_http_only = { description = "Forbids JavaScript from accessing the cookie, for example, through the `Document.cookie` property.", required = false,
              type     = "boolean",
              default  = true,
            },
          },
          {
            authorization_cookie_secure = { description = "Cookie is only sent to the server when a request is made with the https: scheme (except on localhost), and therefore is more resistant to man-in-the-middle attacks.", required = false,
              type     = "boolean",
            },
          },
          {
            preserve_query_args = { description = "With this parameter, you can preserve request query arguments even when doing authorization code flow.", required = false,
              type     = "boolean",
              default  = false,
            },
          },
          {
            token_endpoint = typedefs.url {
              required = false,
            },
          },
          {
            token_endpoint_auth_method = { description = "The token endpoint authentication method: - `client_secret_basic`: send `client_id` and `client_secret` in `Authorization: Basic` header - `client_secret_post`: send `client_id` and `client_secret` as part of the body - `client_secret_jwt`: send client assertion signed with the `client_secret` as part of the body - `private_key_jwt`:  send client assertion signed with the `private key` as part of the body - `none`: do not authenticate", required = false,
              type     = "string",
              one_of   = {
                "client_secret_basic",
                "client_secret_post",
                "client_secret_jwt",
                "private_key_jwt",
                "tls_client_auth",
                "self_signed_tls_client_auth",
                "none",
              },
            },
          },
          {
            token_headers_names = { description = "Extra header names passed to the token endpoint.", required = false,
              type     = "array",
              elements = {
                type   = "string",
              },
            },
          },
          {
            token_headers_values = { description = "Extra header values passed to the token endpoint.", required = false,
              type     = "array",
              elements = {
                type   = "string",
              },
            },
          },
          {
            token_headers_client = { description = "Extra headers passed from the client to the token endpoint.", required = false,
              type     = "array",
              elements = {
                type   = "string",
              },
            },
          },
          {
            token_headers_replay = { description = "The names of token endpoint response headers to forward to the downstream client.", required = false,
              type     = "array",
              elements = {
                type   = "string",
              },
            },
          },
          {
            token_headers_prefix = { description = "Add a prefix to the token endpoint response headers before forwarding them to the downstream client.", required = false,
              type     = "string",
            },
          },
          {
            token_headers_grants = { description = "Enable the sending of the token endpoint response headers only with certain grants: - `password`: with OAuth password grant - `client_credentials`: with OAuth client credentials grant - `authorization_code`: with authorization code flow - `refresh_token` with refresh token grant", required = false,
              type     = "array",
              elements = {
                type   = "string",
                one_of = {
                  "password",
                  "client_credentials",
                  "authorization_code",
                  "refresh_token",
                },
              },
            },
          },
          {
            token_post_args_names = { description = "Extra post argument names passed to the token endpoint.", required = false,
              type     = "array",
              elements = {
                type   = "string",
              },
            },
          },
          {
            token_post_args_values = { description = "Extra post argument values passed to the token endpoint.", required = false,
              type     = "array",
              elements = {
                type   = "string",
              },
            },
          },
          {
            token_post_args_client = { description = "Pass extra arguments from the client to the OpenID-Connect plugin. If arguments exist, the client can pass them using: - Query parameters - Request Body - Reqest Header  This parameter can be used with `scope` values, like this:  `config.token_post_args_client=scope`  In this case, the token would take the `scope` value from the query parameter or from the request body or from the header and send it to the token endpoint.", required = false,
              type     = "array",
              elements = {
                type   = "string",
              },
            },
          },
          {
            introspection_endpoint = typedefs.url {
              required = false,
            },
          },
          {
            introspection_endpoint_auth_method = { description = "The introspection endpoint authentication method: - `client_secret_basic`: send `client_id` and `client_secret` in `Authorization: Basic` header - `client_secret_post`: send `client_id` and `client_secret` as part of the body - `client_secret_jwt`: send client assertion signed with the `client_secret` as part of the body - `private_key_jwt`:  send client assertion signed with the `private key` as part of the body - `none`: do not authenticate", required = false,
              type     = "string",
              one_of   = {
                "client_secret_basic",
                "client_secret_post",
                "client_secret_jwt",
                "private_key_jwt",
                "tls_client_auth",
                "self_signed_tls_client_auth",
                "none",
              },
            },
          },
          {
            introspection_hint = { description = "Introspection hint parameter value passed to the introspection endpoint.", required = false,
              type     = "string",
              default  = "access_token",
            },
          },
          {
            introspection_check_active = { description = "Check that the introspection response has an `active` claim with a value of `true`.", required = false,
              type     = "boolean",
              default  = true,
            },
          },
          {
            introspection_accept = { description = "The value of `Accept` header for introspection requests: - `application/json`: introspection response as JSON - `application/token-introspection+jwt`: introspection response as JWT (from the current IETF draft document) - `application/jwt`: introspection response as JWT (from the obsolete IETF draft document)", required = false,
              type     = "string",
              default  = "application/json",
              one_of   = {
                "application/json",
                "application/token-introspection+jwt",
                "application/jwt",
              },
            },
          },
          {
            introspection_headers_names = { description = "Extra header names passed to the introspection endpoint.", required = false,
              type     = "array",
              elements = {
                type   = "string",
              },
            },
          },
          {
            introspection_headers_values = { description = "Extra header values passed to the introspection endpoint.", required = false,
              type     = "array",
              elements = {
                type   = "string",
              },
            },
          },
          {
            introspection_headers_client = { description = "Extra headers passed from the client to the introspection endpoint.", required = false,
              type     = "array",
              elements = {
                type   = "string",
              },
            },
          },
          {
            introspection_post_args_names = { description = "Extra post argument names passed to the introspection endpoint.", required = false,
              type     = "array",
              elements = {
                type   = "string",
              },
            },
          },
          {
            introspection_post_args_values = { description = "Extra post argument values passed to the introspection endpoint.", required = false,
              type     = "array",
              elements = {
                type   = "string",
              },
            },
          },
          {
            introspection_post_args_client = { description = "Extra post arguments passed from the client to the introspection endpoint.", required = false,
              type     = "array",
              elements = {
                type   = "string",
              },
            },
          },
          {
            introspect_jwt_tokens = { description = "Specifies whether to introspect the JWT access tokens (can be used to check for revocations).", required = false,
              type     = "boolean",
              default  = false,
            },
          },
          {
            revocation_endpoint = typedefs.url {
              required = false,
            },
          },
          {
            revocation_endpoint_auth_method = { description = "The revocation endpoint authentication method: - `client_secret_basic`: send `client_id` and `client_secret` in `Authorization: Basic` header - `client_secret_post`: send `client_id` and `client_secret` as part of the body - `client_secret_jwt`: send client assertion signed with the `client_secret` as part of the body - `private_key_jwt`:  send client assertion signed with the `private key` as part of the body - `none`: do not authenticate", required = false,
              type     = "string",
              one_of   = {
                "client_secret_basic",
                "client_secret_post",
                "client_secret_jwt",
                "private_key_jwt",
                "tls_client_auth",
                "self_signed_tls_client_auth",
                "none",
              },
            },
          },
          {
            end_session_endpoint = typedefs.url {
              required = false,
            },
          },
          {
            userinfo_endpoint = typedefs.url {
              required = false,
            },
          },
          {
            userinfo_accept = { description = "The value of `Accept` header for user info requests: - `application/json`: user info response as JSON - `application/jwt`: user info response as JWT (from the obsolete IETF draft document)", required = false,
              type     = "string",
              default  = "application/json",
              one_of   = {
                "application/json",
                "application/jwt",
              },
            },
          },
          {
            userinfo_headers_names = { description = "Extra header names passed to the user info endpoint.", required = false,
              type     = "array",
              elements = {
                type   = "string",
              },
            },
          },
          {
            userinfo_headers_values = { description = "Extra header values passed to the user info endpoint.", required = false,
              type     = "array",
              elements = {
                type   = "string",
              },
            },
          },
          {
            userinfo_headers_client = { description = "Extra headers passed from the client to the user info endpoint.", required = false,
              type     = "array",
              elements = {
                type   = "string",
              },
            },
          },
          {
            userinfo_query_args_names = { description = "Extra query argument names passed to the user info endpoint.", required = false,
              type     = "array",
              elements = {
                type   = "string",
              },
            },
          },
          {
            userinfo_query_args_values = { description = "Extra query argument values passed to the user info endpoint.", required = false,
              type     = "array",
              elements = {
                type   = "string",
              },
            },
          },
          {
            userinfo_query_args_client = { description = "Extra query arguments passed from the client to the user info endpoint.", required = false,
              type     = "array",
              elements = {
                type   = "string",
              },
            },
          },
          {
            token_exchange_endpoint = typedefs.url {
              required = false,
            },
          },
          {
            session_secret = { description = "The session secret.", required = false,
              type     = "string",
              encrypted = true,
              referenceable = true,
            },
          },
          {
            session_audience = { description = "The session audience, which is the intended target application. For example `\"my-application\"`.", required = false,
              type     = "string",
              default  = "default",
            },
          },
          {
            session_cookie_name = { description = "The session cookie name.", required = false,
              type     = "string",
              default  = "session",
            },
          },
          {
            session_remember = { description = "Enables or disables persistent sessions.", required = false,
              type     = "boolean",
              default  = false,
            },
          },
          {
            session_remember_cookie_name = { description = "Persistent session cookie name. Use with the `remember` configuration parameter.", required = false,
              type     = "string",
              default  = "remember",
            },
          },
          {
            session_remember_rolling_timeout = { description = "Specifies how long the persistent session is considered valid in seconds. 0 disables the checks and rolling.", required = false,
              type     = "number",
              default  = 604800,
            },
          },
          {
            session_remember_absolute_timeout = { description = "Limits how long the persistent session can be renewed in seconds, until re-authentication is required. 0 disables the checks.", required = false,
              type     = "number",
              default  = 2592000,
            },
          },
          {
            session_idling_timeout = { description = "Specifies how long the session can be inactive until it is considered invalid in seconds. 0 disables the checks and touching.", required = false,
              type     = "number",
              default  = 900,
            },
          },
          {
            session_rolling_timeout = { description = "Specifies how long the session can be used in seconds until it needs to be renewed. 0 disables the checks and rolling.", required = false,
              type     = "number",
              default  = 3600,
            },
          },
          {
            session_absolute_timeout = { description = "Limits how long the session can be renewed in seconds, until re-authentication is required. 0 disables the checks.", required = false,
              type     = "number",
              default  = 86400,
            },
          },
          {
            session_cookie_path = typedefs.path {
              required = false,
              default  = "/",
            },
          },
          {
            session_cookie_domain = { description = "The session cookie Domain flag.", required = false,
              type     = "string",
            },
          },
          {
            session_cookie_same_site = { description = "Controls whether a cookie is sent with cross-origin requests, providing some protection against cross-site request forgery attacks.", required = false,
              type     = "string",
              default  = "Lax",
              one_of   = {
                "Strict",
                "Lax",
                "None",
                "Default",
              },
            },
          },
          {
            session_cookie_http_only = { description = "Forbids JavaScript from accessing the cookie, for example, through the `Document.cookie` property.",
              required = false,
              type     = "boolean",
              default  = true,
            },
          },
          {
            session_cookie_secure = { description = "Cookie is only sent to the server when a request is made with the https: scheme (except on localhost), and therefore is more resistant to man-in-the-middle attacks.",
              required = false,
              type     = "boolean",
            },
          },
          {
            session_request_headers = session_headers,
          },
          {
            session_response_headers = session_headers,
          },
          {
            session_storage = { description = "The session storage for session data: - `cookie`: stores session data with the session cookie (the session cannot be invalidated or revoked without changing session secret, but is stateless, and doesn't require a database) - `memcache`: stores session data in memcached - `redis`: stores session data in Redis", required = false,
              type     = "string",
              default  = "cookie",
              one_of   = {
                "cookie",
                "memcache", -- TODO: deprecated, to be removed in Kong 4.0
                "memcached",
                "redis",
              },
            },
          },
          {
            session_store_metadata = { description = "Configures whether or not session metadata should be stored. This metadata includes information about the active sessions for a specific audience belonging to a specific subject.", required = false,
              type     = "boolean",
              default  = false,
            },
          },
          {
            session_enforce_same_subject = { description = "When set to `true`, audiences are forced to share the same subject.", required = false,
              type     = "boolean",
              default  = false,
            },
          },
          {
            session_hash_subject = { description = "When set to `true`, the value of subject is hashed before being stored. Only applies when `session_store_metadata` is enabled.", required = false,
              type     = "boolean",
              default  = false,
            },
          },
          {
            session_hash_storage_key = { description = "When set to `true`, the storage key (session ID) is hashed for extra security. Hashing the storage key means it is impossible to decrypt data from the storage without a cookie.", required = false,
              type     = "boolean",
              default  = false,
            },
          },
          {
            session_memcached_prefix = { description = "The memcached session key prefix.", required = false,
              type     = "string",
            },
          },
          {
            session_memcached_socket = { description = "The memcached unix socket path.", required = false,
              type     = "string",
            },
          },
          {
            session_memcached_host = { description = "The memcached host.", required = false,
              type     = "string",
              default  = "127.0.0.1",
            },
          },
          {
            session_memcached_port = typedefs.port {
              required = false,
              default  = 11211,
            },
          },
          {
            session_redis_prefix = { description = "The Redis session key prefix.", required = false,
              type     = "string",
            },
          },
          {
            session_redis_socket = { description = "The Redis unix socket path.", required = false,
              type     = "string",
            },
          },
          {
            session_redis_host = { description = "The Redis host", required = false,
              type     = "string",
              default  = "127.0.0.1",
            },
          },
          {
            session_redis_port = typedefs.port {
              required = false,
              default  = 6379,
            },
          },
          {
            session_redis_username = { description = "Username to use for Redis connection when the `redis` session storage is defined and ACL authentication is desired. If undefined, ACL authentication will not be performed. This requires Redis v6.0.0+. To be compatible with Redis v5.x.y, you can set it to `default`.", required = false,
              type = "string",
              referenceable = true,
            },
          },
          {
            session_redis_password = { description = "Password to use for Redis connection when the `redis` session storage is defined. If undefined, no AUTH commands are sent to Redis.", required = false,
              type = "string",
              encrypted = true,
              referenceable = true,
            },
          },
          {
            session_redis_connect_timeout = { description = "Session redis connection timeout in milliseconds.", required = false,
              type = "integer",
            },
          },
          {
            session_redis_read_timeout = { description = "Session redis read timeout in milliseconds.", required = false,
              type = "integer",
            },
          },
          {
            session_redis_send_timeout = { description = "Session redis send timeout in milliseconds.", required = false,
              type = "integer",
            },
          },
          {
            session_redis_ssl = { description = "Use SSL/TLS for Redis connection.", required = false,
              type     = "boolean",
              default  = false,
            },
          },
          {
            session_redis_ssl_verify = { description = "Verify identity provider server certificate.", required = false,
              type     = "boolean",
              default  = false,
            },
          },
          {
            session_redis_server_name = { description = "The SNI used for connecting the Redis server.", required = false,
              type     = "string",
            },
          },
          {
            session_redis_cluster_nodes = { description = "The Redis cluster node host. Takes an array of host records, with either `ip` or `host`, and `port` values.", required = false,
              type = "array",
              elements = {
                type = "record",
                fields = {
                  {
                    ip = typedefs.host {
                      required = true,
                      default  = "127.0.0.1",
                    },
                  },
                  {
                    port = typedefs.port {
                      default = 6379,
                    },
                  },
                },
              },
            },
          },
          {
            session_redis_cluster_max_redirections = { description = "The Redis cluster maximum redirects.", required = false,
              type = "integer",
            },
          },
          {
            reverify = { description = "Specifies whether to always verify tokens stored in the session.", required = false,
              type     = "boolean",
              default  = false,
            },
          },
          {
            jwt_session_claim = { description = "The claim to match against the JWT session cookie.", required = false,
              type     = "string",
              default  = "sid",
            },
          },
          {
            jwt_session_cookie = { description = "The name of the JWT session cookie.", required = false,
              type     = "string",
            },
          },
          {
            bearer_token_param_type = { description = "Where to look for the bearer token: - `header`: search the HTTP headers - `query`: search the URL's query string - `body`: search the HTTP request body - `cookie`: search the HTTP request cookies specified with `config.bearer_token_cookie_name`", required = false,
              type     = "array",
              default  = {
                "header",
                "query",
                "body",
              },
              elements = {
                type   = "string",
                one_of = {
                  "header",
                  "cookie",
                  "query",
                  "body",
                },
              },
            },
          },
          {
            bearer_token_cookie_name = { description = "The name of the cookie in which the bearer token is passed.", required = false,
              type     = "string",
            },
          },
          {
            client_credentials_param_type = { description = "Where to look for the client credentials: - `header`: search the HTTP headers - `query`: search the URL's query string - `body`: search from the HTTP request body", required = false,
              type     = "array",
              default  = {
                "header",
                "query",
                "body",
              },
              elements = {
                type   = "string",
                one_of = {
                  "header",
                  "query",
                  "body",
                },
              },
            },
          },
          {
            password_param_type = { description = "Where to look for the username and password: - `header`: search the HTTP headers - `query`: search the URL's query string - `body`: search the HTTP request body", required = false,
              type     = "array",
              default  = {
                "header",
                "query",
                "body",
              },
              elements = {
                type   = "string",
                one_of = {
                  "header",
                  "query",
                  "body",
                },
              },
            },
          },
          {
            id_token_param_type = { description = "Where to look for the id token: - `header`: search the HTTP headers - `query`: search the URL's query string - `body`: search the HTTP request body", required = false,
              type     = "array",
              default  = {
                "header",
                "query",
                "body",
              },
              elements = {
                type   = "string",
                one_of = {
                  "header",
                  "query",
                  "body",
                },
              },
            },
          },
          {
            id_token_param_name = { description = "The name of the parameter used to pass the id token.", required = false,
              type     = "string",
            },
          },
          {
            refresh_token_param_type = { description = "Where to look for the refresh token: - `header`: search the HTTP headers - `query`: search the URL's query string - `body`: search the HTTP request body", required = false,
              type     = "array",
              default  = {
                "header",
                "query",
                "body",
              },
              elements = {
                type   = "string",
                one_of = {
                  "header",
                  "query",
                  "body",
                },
              },
            },
          },
          {
            refresh_token_param_name = { description = "The name of the parameter used to pass the refresh token.", required = false,
              type     = "string",
            },
          },
          {
            refresh_tokens = { description = "Specifies whether the plugin should try to refresh (soon to be) expired access tokens if the plugin has a `refresh_token` available.", required = false,
              type     = "boolean",
              default  = true,
            },
          },
          {
            upstream_headers_claims = { description = "The upstream header claims. If multiple values are set, it means the claim is inside a nested object of the token payload.", required = false,
              type     = "array",
              elements = {
                type   = "string",
              },
            },
          },
          {
            upstream_headers_names = { description = "The upstream header names for the claim values.", required = false,
              type     = "array",
              elements = {
                type   = "string",
              },
            },
          },
          {
            upstream_access_token_header = { description = "The upstream access token header.", required = false,
              type     = "string",
              default  = "authorization:bearer",
            },
          },
          {
            upstream_access_token_jwk_header = { description = "The upstream access token JWK header.", required = false,
              type     = "string",
            },
          },
          {
            upstream_id_token_header = { description = "The upstream id token header.", required = false,
              type     = "string",
            },
          },
          {
            upstream_id_token_jwk_header = { description = "The upstream id token JWK header.", required = false,
              type     = "string",
            },
          },
          {
            upstream_refresh_token_header = { description = "The upstream refresh token header.", required = false,
              type     = "string",
            },
          },
          {
            upstream_user_info_header = { description = "The upstream user info header.", required = false,
              type     = "string",
            },
          },
          {
            upstream_user_info_jwt_header = { description = "The upstream user info JWT header (in case the user info returns a JWT response).", required = false,
              type     = "string",
            },
          },
          {
            upstream_introspection_header = { description = "The upstream introspection header.", required = false,
              type     = "string",
            },
          },
          {
            upstream_introspection_jwt_header = {
              required = false,
              type     = "string",
            },
          },
          {
            upstream_session_id_header = { description = "The upstream session id header.", required = false,
              type     = "string",
            },
          },
          {
            downstream_headers_claims = { description = "The downstream header claims. If multiple values are set, it means the claim is inside a nested object of the token payload.", required = false,
              type     = "array",
              elements = {
                type   = "string",
              },
            },
          },
          {
            downstream_headers_names = { description = "The downstream header names for the claim values.", required = false,
              type     = "array",
              elements = {
                type   = "string",
              },
            },
          },
          {
            downstream_access_token_header = { description = "The downstream access token header.", required = false,
              type     = "string",
            },
          },
          {
            downstream_access_token_jwk_header = { description = "The downstream access token JWK header.", required = false,
              type     = "string",
            },
          },
          {
            downstream_id_token_header = { description = "The downstream id token header.", required = false,
              type     = "string",
            },
          },
          {
            downstream_id_token_jwk_header = { description = "The downstream id token JWK header.", required = false,
              type     = "string",
            },
          },
          {
            downstream_refresh_token_header = { description = "The downstream refresh token header.", required = false,
              type     = "string",
            },
          },
          {
            downstream_user_info_header = { description = "The downstream user info header.", required = false,
              type     = "string",
            },
          },
          {
            downstream_user_info_jwt_header = { description = "The downstream user info JWT header (in case the user info returns a JWT response).", required = false,
              type     = "string",
            },
          },
          {
            downstream_introspection_header = { description = "The downstream introspection header.", required = false,
              type     = "string",
            },
          },
          {
            downstream_introspection_jwt_header = {
              required = false,
              type     = "string",
            },
          },
          {
            downstream_session_id_header = { description = "The downstream session id header.", required = false,
              type     = "string",
            },
          },
          {
            login_methods = { description = "Enable login functionality with specified grants.", required = false,
              type     = "array",
              default  = {
                "authorization_code",
              },
              elements = {
                type   = "string",
                one_of = {
                  "password",
                  "client_credentials",
                  "authorization_code",
                  "bearer",
                  "introspection",
                  "userinfo",
                  "kong_oauth2",
                  "refresh_token",
                  "session",
                }
              },
            },
          },
          {
            login_action = { description = "What to do after successful login: - `upstream`: proxy request to upstream service - `response`: terminate request with a response - `redirect`: redirect to a different location", required = false,
              type     = "string",
              default  = "upstream",
              one_of   = {
                "upstream",
                "response",
                "redirect",
              },
            },
          },
          {
            login_tokens = { description = "What tokens to include in `response` body or `redirect` query string or fragment: - `id_token`: include id token - `access_token`: include access token - `refresh_token`: include refresh token - `tokens`: include the full token endpoint response - `introspection`: include introspection response", required = false,
              type     = "array",
              default  = {
                "id_token",
              },
              elements = {
                type   = "string",
                one_of = {
                  "id_token",
                  "access_token",
                  "refresh_token",
                  "tokens",
                  "introspection",
                }
              },
            },
          },
          {
            login_redirect_mode = { description = "Where to place `login_tokens` when using `redirect` `login_action`: - `query`: place tokens in query string - `fragment`: place tokens in url fragment (not readable by servers)", required = false,
              type     = "string",
              default  = "fragment",
              one_of   = {
                "query",
                "fragment",
              },
            },
          },
          {
            logout_query_arg = { description = "The request query argument that activates the logout.", required = false,
              type     = "string",
            },
          },
          {
            logout_post_arg = { description = "The request body argument that activates the logout.", required = false,
              type     = "string",
            },
          },
          {
            logout_uri_suffix = { description = "The request URI suffix that activates the logout.", required = false,
              type     = "string",
            },
          },
          {
            logout_methods = { description = "The request methods that can activate the logout: - `POST`: HTTP POST method - `GET`: HTTP GET method - `DELETE`: HTTP DELETE method", required = false,
              type     = "array",
              default  = {
                "POST",
                "DELETE",
              },
              elements = {
                type   = "string",
                one_of = {
                  "POST",
                  "GET",
                  "DELETE",
                },
              },
            },
          },
          {
            logout_revoke = { description = "Revoke tokens as part of the logout.\n\nFor more granular token revocation, you can also adjust the `logout_revoke_access_token` and `logout_revoke_refresh_token` parameters.", required = false,
              type     = "boolean",
              default  = false,
            },
          },
          {
            logout_revoke_access_token = { description = "Revoke the access token as part of the logout. Requires `logout_revoke` to be set to `true`.", required = false,
              type     = "boolean",
              default  = true,
            },
          },
          {
            logout_revoke_refresh_token = { description = "Revoke the refresh token as part of the logout. Requires `logout_revoke` to be set to `true`.", required = false,
              type     = "boolean",
              default  = true,
            },
          },
          {
            consumer_claim = { description = "The claim used for consumer mapping. If multiple values are set, it means the claim is inside a nested object of the token payload.", required = false,
              type     = "array",
              elements = {
                type   = "string",
              },
            },
          },
          {
            consumer_by = { description = "Consumer fields used for mapping: - `id`: try to find the matching Consumer by `id` - `username`: try to find the matching Consumer by `username` - `custom_id`: try to find the matching Consumer by `custom_id`", required = false,
              type     = "array",
              default  = {
                "username",
                "custom_id",
              },
              elements = {
                type   = "string",
                one_of = {
                  "id",
                  "username",
                  "custom_id",
                },
              },
            },
          },
          {
            consumer_optional = { description = "Do not terminate the request if consumer mapping fails.", required = false,
              type     = "boolean",
              default  = false,
            },
          },
          {
            credential_claim = { description = "The claim used to derive virtual credentials (e.g. to be consumed by the rate-limiting plugin), in case the consumer mapping is not used. If multiple values are set, it means the claim is inside a nested object of the token payload.", required = false,
              type     = "array",
              default  = {
                "sub",
              },
              elements = {
                type   = "string",
              },
            },
          },
          {
            anonymous = { description = "An optional string (consumer UUID or username) value that functions as an “anonymous” consumer if authentication fails. If empty (default null), requests that fail authentication will return a `4xx` HTTP status code. This value must refer to the consumer `id` or `username` attribute, and **not** its `custom_id`.", required = false,
              type     = "string",
            },
          },
          {
            run_on_preflight = { description = "Specifies whether to run this plugin on pre-flight (`OPTIONS`) requests.", required = false,
              type     = "boolean",
              default  = true,
            },
          },
          {
            leeway = { description = "Allow some leeway (in seconds) on the iat claim and ttl / expiry verification.", required = false,
              type     = "number",
              default  = 0,
            },
          },
          {
            verify_parameters = { description = "Verify plugin configuration against discovery.", required = false,
              type     = "boolean",
              default  = false,
            },
          },
          {
            verify_nonce = { description = "Verify nonce on authorization code flow.", required = false,
              type     = "boolean",
              default  = true,
            },
          },
          {
            verify_claims = { description = "Verify tokens for standard claims.", required = false,
              type     = "boolean",
              default  = true,
            },
          },
          {
            verify_signature = { description = "Verify signature of tokens.", required = false,
              type     = "boolean",
              default  = true,
            },
          },
          {
            ignore_signature = { description = "Skip the token signature verification on certain grants: - `password`: OAuth password grant - `client_credentials`: OAuth client credentials grant - `authorization_code`: authorization code flow - `refresh_token`: OAuth refresh token grant - `session`: session cookie authentication - `introspection`: OAuth introspection - `userinfo`: OpenID Connect user info endpoint authentication", required = false,
              type     = "array",
              default  = {
              },
              elements = {
                type   = "string",
                one_of = {
                  "password",
                  "client_credentials",
                  "authorization_code",
                  "refresh_token",
                  "session",
                  "introspection",
                  "userinfo",
                },
              },
            },
          },
          {
            enable_hs_signatures = { description = "Enable shared secret, for example, HS256, signatures (when disabled they will not be accepted).", required = false,
              type     = "boolean",
              default  = false,
            },
          },
          {
            disable_session = { description = "Disable issuing the session cookie with the specified grants.", required = false,
              type     = "array",
              elements = {
                type   = "string",
                one_of = {
                  "password",
                  "client_credentials",
                  "authorization_code",
                  "bearer",
                  "introspection",
                  "userinfo",
                  "kong_oauth2",
                  "refresh_token",
                  "session",
                },
              },
            },
          },
          {
            cache_ttl = { description = "The default cache ttl in seconds that is used in case the cached object does not specify the expiry.", required = false,
              type     = "number",
              default  = 3600,
            },
          },
          {
            cache_ttl_max = { description = "The maximum cache ttl in seconds (enforced).", required = false,
              type     = "number",
            },
          },
          {
            cache_ttl_min = { description = "The minimum cache ttl in seconds (enforced).", required = false,
              type     = "number",
            },
          },
          {
            cache_ttl_neg = { description = "The negative cache ttl in seconds.", required = false,
              type     = "number",
            },
          },
          {
            cache_ttl_resurrect = { description = "The resurrection ttl in seconds.", required = false,
              type     = "number",
            },
          },
          {
            cache_tokens = { description = "Cache the token endpoint requests.", required = false,
              type     = "boolean",
              default  = true,
            },
          },
          {
            cache_tokens_salt = { description = "Salt used for generating the cache key that is used for caching the token endpoint requests.", required = false,
              type     = "string",
              auto     = true,
            },
          },
          {
            cache_introspection = { description = "Cache the introspection endpoint requests.", required = false,
              type     = "boolean",
              default  = true,
            },
          },
          {
            cache_token_exchange = { description = "Cache the token exchange endpoint requests.", required = false,
              type     = "boolean",
              default  = true,
            },
          },
          {
            cache_user_info = { description = "Cache the user info requests.", required = false,
              type     = "boolean",
              default  = true,
            },
          },
          {
            search_user_info = { description = "Specify whether to use the user info endpoint to get additional claims for consumer mapping, credential mapping, authenticated groups, and upstream and downstream headers.", required = false,
              type     = "boolean",
              default  = false,
            },
          },
          {
            hide_credentials = { description = "Remove the credentials used for authentication from the request. If multiple credentials are sent with the same request, the plugin will remove those that were used for successful authentication.", required = false,
              type     = "boolean",
              default  = false,
            },
          },
          {
            http_version = { description = "The HTTP version used for the requests by this plugin: - `1.1`: HTTP 1.1 (the default) - `1.0`: HTTP 1.0", required = false,
              type     = "number",
              default  = 1.1,
              custom_validator = function(v)
                if v == 1.0 or v == 1.1 then
                  return true
                end

                return nil, "must be 1.0 or 1.1"
              end
            },
          },
          {
            http_proxy = typedefs.url {
              required = false,
            },
          },
          {
            http_proxy_authorization = { description = "The HTTP proxy authorization.", required = false,
              type     = "string",
            },
          },
          {
            https_proxy = typedefs.url {
              required = false,
            },
          },
          {
            https_proxy_authorization = { description = "The HTTPS proxy authorization.", required = false,
              type     = "string",
            },
          },
          {
            no_proxy = { description = "Do not use proxy with these hosts.", required = false,
              type     = "string",
            },
          },
          {
            keepalive = { description = "Use keepalive with the HTTP client.", required = false,
              type     = "boolean",
              default  = true,
            },
          },
          {
            ssl_verify = { description = "Verify identity provider server certificate.", required = false,
              type     = "boolean",
              default  = false,
            },
          },
          {
            timeout = { description = "Network IO timeout in milliseconds.", required = false,
              type     = "number",
              default  = 10000,
            },
          },
          {
            display_errors = { description = "Display errors on failure responses.", required = false,
              type     = "boolean",
              default  = false,
            },
          },
          {
            by_username_ignore_case = { description = "If `consumer_by` is set to `username`, specify whether `username` can match consumers case-insensitively.", required = false,
              type     = "boolean",
              default  = false,
            },
          },
          -- Not yet implemented
          -- {
          --   resolve_aggregated_claims = {
          --     required = false,
          --     type     = "boolean",
          --     default  = false,
          --   },
          -- },
          {
            resolve_distributed_claims = { description = "Distributed claims are represented by the `_claim_names` and `_claim_sources` members of the JSON object containing the claims. If this parameter is set to `true`, the plugin explicitly resolves these distributed claims.", required = false,
              type     = "boolean",
              default  = false,
            },
          },
          {
            expose_error_code = { description = "Specifies whether to expose the error code header, as defined in RFC 6750. If an authorization request fails, this header is sent in the response. Set to `false` to disable.",
              type = "boolean",
              default = true,
            },
          },
          {
            token_cache_key_include_scope = { description = "Include the scope in the token cache key, so token with different scopes are considered diffrent tokens.",
              type = "boolean",
              default = false,
            },
          },
          {
            introspection_token_param_name = { description = "Designate token's parameter name for introspection.", required = false,
              type = "string",
              default = "token",
            }
          },
          {
            using_pseudo_issuer = { description = "If the plugin uses a pseudo issuer. When set to true, the plugin will not discover the configuration from the issuer URL.",
              type = "boolean",
              default = false,
            }
          },
          {
            revocation_token_param_name = { description = "Designate token's parameter name for revocation.", required = false,
              type = "string",
              default = "token",
            }
          },
          {
            proof_of_possession_mtls = { description = "Enable mtls proof of possession. If set to strict, all tokens (from supported auth_methods: bearer, introspection, and session granted with bearer or introspection) are verified, if set to optional, only tokens that contain the certificate hash claim are verified. If the verification fails, the request will be rejected with 401.",
              type = "string",
              one_of = {
                "off", "strict", "optional",
              },
              default = "off",
            }
          },
          {
            proof_of_possession_auth_methods_validation = { description = "If set to true, only the auth_methods that are compatible with Proof of Possession (PoP) can be configured when PoP is enabled. If set to false, all auth_methods will be configurable and PoP checks will be silently skipped for those auth_methods that are not compatible with PoP.",
              type = "boolean",
              default = true,
            }
          },
          {
            tls_client_auth_cert_id = typedefs.uuid {
              description = "ID of the Certificate entity representing the client certificate to use for mTLS client authentication for connections between Kong and the Auth Server.",
              required = false,
              auto = false,
            },
          },
          {
            tls_client_auth_ssl_verify = { description = "Verify identity provider server certificate during mTLS client authentication.", required = false,
              type = "boolean",
              default = true,
            },
          },
          {
            mtls_token_endpoint = typedefs.url {
              description = "Alias for the token endpoint to be used for mTLS client authentication. If set it overrides the value in `mtls_endpoint_aliases` returned by the discovery endpoint.",
              required = false,
            },
          },
          {
            mtls_introspection_endpoint = typedefs.url {
              description = "Alias for the introspection endpoint to be used for mTLS client authentication. If set it overrides the value in `mtls_endpoint_aliases` returned by the discovery endpoint.",
              required = false,
            },
          },
          {
            mtls_revocation_endpoint = typedefs.url {
              description = "Alias for the introspection endpoint to be used for mTLS client authentication. If set it overrides the value in `mtls_endpoint_aliases` returned by the discovery endpoint.",
              required = false,
            },
          },
        },
        shorthand_fields = {
          -- TODO: deprecated forms, to be removed in Kong 4.0
          {
            authorization_cookie_lifetime = {
              type = "number",
              func = function(value)
                return { authorization_rolling_timeout = value }
              end,
            },
          },
          {
            authorization_cookie_samesite = {
              type = "string",
              func = function(value)
                if value == "off" then
                  value = "Default"
                end
                return { authorization_cookie_same_site = value }
              end,
            },
          },
          {
            authorization_cookie_httponly = {
              type = "boolean",
              func = function(value)
                return { authorization_cookie_http_only = value }
              end,
            },
          },
          {
            session_cookie_lifetime = {
              type = "number",
              func = function(value)
                return { session_rolling_timeout = value }
              end,
            },
          },
          {
            session_cookie_idletime = {
              type = "number",
              func = function(value)
                return { session_idling_timeout = value }
              end,
            },
          },
          {
            session_cookie_samesite = {
              type = "string",
              func = function(value)
                if value == "off" then
                  value = "Lax"
                end
                return { session_cookie_same_site = value }
              end,
            },
          },
          {
            session_cookie_httponly = {
              type = "boolean",
              func = function(value)
                return { session_cookie_http_only = value }
              end,
            },
          },
          {
            session_memcache_prefix = {
              type = "string",
              func = function(value)
                return { session_memcached_prefix = value }
              end,
            },
          },
          {
            session_memcache_socket = {
              type = "string",
              func = function(value)
                return { session_memcached_socket = value }
              end,
            },
          },
          {
            session_memcache_host = {
              type = "string",
              func = function(value)
                return { session_memcached_host = value }
              end,
            },
          },
          {
            session_memcache_port = {
              type = "integer",
              func = function(value)
                return { session_memcached_port = value }
              end,
            },
          },
          {
            session_redis_cluster_maxredirections = {
              type = "integer",
              func = function(value)
                return { session_redis_cluster_max_redirections = value }
              end,
            },
          },
          {
            session_cookie_renew = {
              type = "number",
              func = function()
                -- new library calculates this
                ngx.log(ngx.INFO, "[openid-connect] session_cookie_renew option does not exist anymore")
              end,
            },
          },
          {
            session_cookie_maxsize = {
              type = "integer",
              func = function()
                -- new library has this hard coded
                ngx.log(ngx.INFO, "[openid-connect] session_cookie_maxsize option does not exist anymore")
              end,
            },
          },
          {
            session_strategy = {
              type = "string",
              func = function()
                -- new library supports only the so called regenerate strategy
                ngx.log(ngx.INFO, "[openid-connect] session_strategy option does not exist anymore")
              end,
            },
          },
          {
            session_compressor = {
              type = "string",
              func = function()
                -- new library decides this based on data size
                ngx.log(ngx.INFO, "[openid-connect] session_compressor option does not exist anymore")
              end,
            },
          },
        },
      },
    },
  },
}


return config
