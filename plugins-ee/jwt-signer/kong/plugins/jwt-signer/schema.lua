-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local typedefs  = require "kong.db.schema.typedefs"
local arguments = require "kong.plugins.jwt-signer.arguments"
local cache     = require "kong.plugins.jwt-signer.cache"
local log       = require "kong.plugins.jwt-signer.log"


local get_phase = ngx.get_phase


local function validate_tokens(conf)
  local phase = get_phase()
  if phase == "access" or phase == "content" then
    local args = arguments(conf)

    local access_token_jwks_uri = args.get_conf_arg("access_token_jwks_uri")
    if access_token_jwks_uri then
      local ok, err = cache.load_keys(access_token_jwks_uri)
      if not ok then
        log.notice("unable to load access token jwks (", err, ")")
        return false, "unable to load access token jwks"
      end
    end

    local channel_token_jwks_uri = args.get_conf_arg("channel_token_jwks_uri")
    if channel_token_jwks_uri then
      local ok, err = cache.load_keys(channel_token_jwks_uri)
      if not ok then
        log.notice("unable to load channel token jwks (", err, ")")
        return false, "unable to load channel token jwks"
      end
    end

    local access_token_keyset = args.get_conf_arg("access_token_keyset")
    if access_token_keyset then
      local ok, err = cache.load_keys(access_token_keyset)
      if not ok then
        log.notice("unable to load access token keyset (", err, ")")
        return false, "unable to load access token keyset"
      end
    end

    local channel_token_keyset = args.get_conf_arg("channel_token_keyset")
    if channel_token_keyset and channel_token_keyset ~= access_token_keyset then
      local ok, err = cache.load_keys(channel_token_keyset)
      if not ok then
        log.notice("unable to load channel token keyset (", err, ")")
        return false, "unable to load channel token keyset"
      end
    end

    if access_token_keyset ~= "kong" and channel_token_keyset ~= "kong" then
      local ok, err = cache.load_keys("kong")
      if not ok then
        log.notice("unable to load kong keyset (", err, ")")
        return false, "unable to load kong keyset"
      end
    end
  end

  return true
end


local config = {
  name = "jwt-signer",
  fields = {
    { consumer = typedefs.no_consumer },
    { protocols = typedefs.protocols_http },
    { consumer_group = typedefs.no_consumer_group },
    { config   = {
        type             = "record",
        custom_validator = validate_tokens,
        fields           = {
          {
            realm = { description = "When authentication or authorization fails, or there is an unexpected error, the plugin sends an `WWW-Authenticate` header with the `realm` attribute value.", type = "string",
              required = false,
            },
          },
          {
            enable_hs_signatures = { description = "Tokens signed with HMAC algorithms such as `HS256`, `HS384`, or `HS512` are not accepted by default. If you need to accept such tokens for verification, enable this setting.", type     = "boolean",
              required = false,
              default  = false,
            },
          },
          {
            enable_instrumentation = { description = "Writes log entries with some added information using `ngx.CRIT` (CRITICAL) level.", type = "boolean",
              default = false,
              required = false,
            },
          },
          {
            access_token_issuer = { description = "The `iss` claim of a signed or re-signed access token is set to this value. Original `iss` claim of the incoming token (possibly introspected) is stored in `original_iss` claim of the newly signed access token.", type = "string",
              default = "kong",
              required = false,
            },
          },
          {
            access_token_keyset = { description = "The name of the keyset containing signing keys.", type = "string",
              default = "kong",
              required = false,
            },
          },
          {
            access_token_jwks_uri =
              typedefs.url {
              required = false, description = "Specify the URI where the plugin can fetch the public keys (JWKS) to verify the signature of the access token."
            },
          },
          {
            access_token_request_header = { description = "This parameter tells the name of the header where to look for the access token.", type = "string",
              default = "Authorization",
              required = false,
            },
          },
          {
            access_token_leeway = { description = "Adjusts clock skew between the token issuer and Kong. The value is added to the token's `exp` claim before checking token expiry against Kong servers' current time in seconds. You can disable access token `expiry` verification altogether with `config.verify_access_token_expiry`.", type = "number",
              default =  0,
              required = false,
            },
          },
          {
            access_token_scopes_required = { description = "Specify the required values (or scopes) that are checked by a claim specified by `config.access_token_scopes_claim`.",
              type = "array",
              elements = { type = "string" },
              required = false,
            },
          },
          {
            access_token_scopes_claim = { description = "Specify the claim in an access token to verify against values of `config.access_token_scopes_required`.",
              type = "array",
              elements = { type = "string" },
              default = { "scope" },
              required = false,
            },
          },
          {
            access_token_consumer_claim = { description = "When you set a value for this parameter, the plugin tries to map an arbitrary claim specified with this configuration parameter (for example, `sub` or `username`) in an access token to Kong consumer entity.", type = "array",
              elements = { type = "string" },
              required = false,
            },
          },
          {
            access_token_consumer_by = { description = "When the plugin tries to apply an access token to a Kong consumer mapping, it tries to find a matching Kong consumer from properties defined using this configuration parameter. The parameter can take an array of alues. Valid values are `id`, `username`, and `custom_id`.", type = "array",
              elements = {
                type = "string",
                one_of = { "id", "username", "custom_id" },
              },
              default = { "username", "custom_id" },
              required = false,
            },
          },
          {
            access_token_upstream_header = { description = "Removes the `config.access_token_request_header` from the request after reading its value. With `config.access_token_upstream_header`, you can specify the upstream header where the plugin adds the Kong signed token. If you don't specify a value, such as use `null` or `\"\"` (empty string), the plugin does not even try to sign or re-sign the token.", type = "string",
              default = "Authorization:Bearer",
              required = false,
            },
          },
          {
            access_token_upstream_leeway = { description = "If you want to add or subtract (using a negative value) expiry time (in seconds) of the original access token, you can specify a value that is added to the original access token's `exp` claim.", type = "number",
              default = 0,
              required = false,
            },
          },
          {
            access_token_introspection_endpoint = typedefs.url {
              required = false, description = "When you use `opaque` access tokens and you want to turn on access token introspection, you need to specify the OAuth 2.0 introspection endpoint URI with this configuration parameter."
            },
          },
          {
            access_token_introspection_authorization = { description = "If the introspection endpoint requires client authentication (client being the JWT Signer plugin), you can specify the `Authorization` header's value with this configuration parameter.", type = "string",
              required = false,
            },
          },
          {
            access_token_introspection_body_args = { description = "This parameter allows you to pass URL encoded request body arguments. For example: `resource=` or `a=1&b=&c`.", type = "string",
              required = false,
            },
          },
          {
            access_token_introspection_hint = { description = "If you need to give `hint` parameter when introspecting an access token, use this parameter to specify the value. By default, the plugin sends `hint=access_token`.", type = "string",
              default = "access_token",
              required = false,
            },
          },
          {
            access_token_introspection_jwt_claim = { description = "If your introspection endpoint returns an access token in one of the keys (or claims) within the introspection results (`JSON`). If the key cannot be found, the plugin responds with `401 Unauthorized`. Also if the key is found but cannot be decoded as JWT, it also responds with `401 Unauthorized`.", type = "array",
              elements = { type = "string" },
              required = false,
            },
          },
          {
            access_token_introspection_scopes_required = { description = "Specify the required values (or scopes) that are checked by an introspection claim/property specified by `config.access_token_introspection_scopes_claim`.",
              type = "array",
              elements = { type = "string" },
              required =  false,
            },
          },
          {
            access_token_introspection_scopes_claim = { description = "Specify the claim/property in access token introspection results (`JSON`) to be verified against values of `config.access_token_introspection_scopes_required`. This supports nested claims. For example, with Keycloak you could use `[ \"realm_access\", \"roles\" ]`, hich can be given as `realm_access,roles` (form post). If the claim is not found in access token introspection results, and you have specified `config.access_token_introspection_scopes_required`, the plugin responds with `403 Forbidden`.",
              type = "array",
              elements = { type = "string" },
              default = { "scope" },
              required = true,
            },
          },
          {
            access_token_introspection_consumer_claim = { description = "When you set a value for this parameter, the plugin tries to map an arbitrary claim specified with this configuration parameter (such as `sub` or `username`) in access token introspection results to the Kong consumer entity.", type = "array",
              elements = { type = "string" },
              required = false,
            },
          },
          {
            access_token_introspection_consumer_by = { description = "When the plugin tries to do access token introspection results to Kong consumer mapping, it tries to find a matching Kong consumer from properties defined using this configuration parameter. The parameter can take an array of values.", type = "array",
              elements = {
                type = "string",
                one_of = { "id",  "username", "custom_id" },
              },
              default = { "username", "custom_id" },
              required = false,
            },
          },
          {
            access_token_introspection_leeway = { description = "Adjusts clock skew between the token issuer introspection results and Kong. The value is added to introspection results (`JSON`) `exp` claim/property before checking token expiry against Kong servers current time in seconds. You can disable access token introspection `expiry` verification altogether with `config.verify_access_token_introspection_expiry`.", type = "number",
              default = 0,
              required = false,
            },
          },
          {
            access_token_introspection_timeout = { description = "Timeout in milliseconds for an introspection request. The plugin tries to introspect twice if the first request fails for some reason. If both requests timeout, then the plugin runs two times the `config.access_token_introspection_timeout` on access token introspection.", type = "number",
              required = false,
            },
          },
          {
            access_token_signing_algorithm = { description = "When this plugin sets the upstream header as specified with `config.access_token_upstream_header`, re-signs the original access token using the private keys of the JWT Signer plugin. Specify the algorithm that is used to sign the token. The `config.access_token_issuer` specifies which `keyset` is used to sign the new token issued by Kong using the specified signing algorithm.", type = "string",
              one_of = {
                "HS256",
                "HS384",
                "HS512",
                "RS256",
                "RS512",
                "ES256",
                "ES384",
                "ES512",
                "PS256",
                "PS384",
                "PS512",
                "EdDSA",
              },
              default = "RS256",
              required = true,
            },
          },
          {
            access_token_optional = { description = "If an access token is not provided or no `config.access_token_request_header` is specified, the plugin cannot verify the access token. In that case, the plugin normally responds with `401 Unauthorized` (client didn't send a token) or `500 Unexpected` (a configuration error). Use this parameter to allow the request to proceed even when there is no token to check. If the token is provided, then this parameter has no effect", type = "boolean",
              default = false,
              required = false,
            },
          },
          {
            verify_access_token_signature = { description = "Quickly turn access token signature verification off and on as needed.", type = "boolean",
              default = true,
              required = false,
            },
          },
          {
            verify_access_token_expiry = { description = "Quickly turn access token expiry verification off and on as needed.", type = "boolean",
              default = true,
              required = false,
            },
          },
          {
            verify_access_token_scopes = { description = "Quickly turn off and on the access token required scopes verification, specified with `config.access_token_scopes_required`.", type = "boolean",
              default = true,
              required = false,
            },
          },
          {
            verify_access_token_introspection_expiry = { description = "Quickly turn access token introspection expiry verification off and on as needed.", type = "boolean",
              default = true,
              required = false,
            },
          },
          {
            verify_access_token_introspection_scopes = { description = "Quickly turn off and on the access token introspection scopes verification, specified with `config.access_token_introspection_scopes_required`.", type = "boolean",
              default = true,
              required = false,
            },
          },
          {
            cache_access_token_introspection = { description = "Whether to cache access token introspection results.", type = "boolean",
              default = true,
              required = false,
            },
          },
          {
            trust_access_token_introspection = { description = "Use this parameter to enable and disable further checks on a payload before the new token is signed. If you set this to `true`, the expiry or scopes are not checked on a payload.", type = "boolean",
              default = true,
              required = false,
            },
          },
          {
            enable_access_token_introspection = { description = "If you don't want to support opaque access tokens, change this configuration parameter to `false` to disable introspection.", type = "boolean",
              default = true,
              required =  false,
            },
          },
          {
            channel_token_issuer = { description = "The `iss` claim of the re-signed channel token is set to this value, which is `kong` by default. The original `iss` claim of the incoming token (possibly introspected) is stored in the `original_iss` claim of the newly signed channel token.", type = "string",
              default = "kong",
              required = false,
            },
          },
          {
            channel_token_keyset = { description = "The name of the keyset containing signing keys.",
              type = "string",
              default = "kong",
              required = false,
            },
          },
          {
            channel_token_jwks_uri = typedefs.url {
              required = false, description = "If you want to use `config.verify_channel_token_signature`, you must specify the URI where the plugin can fetch the public keys (JWKS) to verify the signature of the channel token. If you don't specify a URI and you pass a JWT token to the plugin, then the plugin responds with `401 Unauthorized`."
            },
          },
          {
            channel_token_request_header = { description = "This parameter tells the name of the header where to look for the channel token. If you don't want to do anything with the channel token, then you can set this to `null` or `\"\"` (empty string).", type = "string",
              required = false,
            },
          },
          {
            channel_token_leeway = { description = "Adjusts clock skew between the token issuer and Kong. The value will be added to token's `exp` claim before checking token expiry against Kong servers current time in seconds. You can disable channel token `expiry` verification altogether with `config.verify_channel_token_expiry`.", type = "number",
              default = 0,
              required = false,
            },
          },
          {
            channel_token_scopes_required = { description = "Specify the required values (or scopes) that are checked by a claim specified by `config.channel_token_scopes_claim`.",
              type = "array",
              elements = { type = "string" },
              required = false,
            },
          },
          {
            channel_token_scopes_claim = { description = "Specify the claim in a channel token to verify against values of `config.channel_token_scopes_required`. This supports nested claims.",
              type = "array",
              elements = { type = "string" },
              default = { "scope" },
              required = false,
            },
          },
          {
            channel_token_consumer_claim = { description = "When you set a value for this parameter, the plugin tries to map an arbitrary claim specified with this configuration parameter. Kong consumers have an `id`, a `username`, and a `custom_id`. If this parameter is enabled but the mapping fails, such as when there's a non-existent Kong consumer, the plugin responds with `403 Forbidden`.", type = "array",
              elements = { type = "string" },
              required = false,
            },
          },
          {
            channel_token_consumer_by = { description = "When the plugin tries to do channel token to Kong consumer mapping, it tries to find a matching Kong consumer from properties defined using this configuration parameter. The parameter can take an array of valid values: `id`, `username`, and `custom_id`.", type = "array",
              elements = {
                type = "string",
                one_of = { "id", "username", "custom_id" },
              },
              default =  { "username", "custom_id" },
            },
          },
          {
            channel_token_upstream_header = { description = "This plugin removes the `config.channel_token_request_header` from the request after reading its value.", type = "string",
              required = false,
            },
          },
          {
            channel_token_upstream_leeway = { description = "If you want to add or perhaps subtract (using negative value) expiry time of the original channel token, you can specify a value that is added to the original channel token's `exp` claim.", type = "number",
              default = 0,
              required = false,
            },
          },
          {
            channel_token_introspection_endpoint = typedefs.url {
              required = false, description = "When you use `opaque` access tokens and you want to turn on access token introspection, you need to specify the OAuth 2.0 introspection endpoint URI with this configuration parameter. Otherwise, the plugin does not try introspection and returns `401 Unauthorized` instead."
            },
          },
          {
            channel_token_introspection_authorization   = {
              description = "When using `opaque` channel tokens, and you want to turn on channel token introspection, you need to specify the OAuth 2.0 introspection endpoint URI with this configuration parameter. Otherwise the plugin will not try introspection, and instead returns `401 Unauthorized` when using opaque channel tokens.",
              type = "string",
              elements = { type = "string" },
              required = false,
            },
          },
          {
            channel_token_introspection_body_args = { description = "If you need to pass additional body arguments to introspection endpoint when the plugin introspects the opaque channel token, you can use this config parameter to specify them. You should URL encode the value. For example: `resource=` or `a=1&b=&c`.", type = "string",
              elements = { type = "string" },
              required = false,
            },
          },
          {
            channel_token_introspection_hint = { description = "If you need to give `hint` parameter when introspecting a channel token, you can use this parameter to specify the value of such parameter. By default, a `hint` isn't sent with channel token introspection.", type = "string",
              elements = { type = "string" },
              required = false,
            },
          },
          {
            channel_token_introspection_jwt_claim = { description = "If your introspection endpoint returns a channel token in one of the keys (or claims) in the introspection results (`JSON`), the plugin can use that value instead of the introspection results when doing expiry verification and signing of the new token issued by Kong.", type = "array",
              elements = { type = "string" },
              required = false,
            },
          },
          {
            channel_token_introspection_scopes_required = { description = "Use this parameter to specify the required values (or scopes) that are checked by an introspection claim/property specified by `config.channel_token_introspection_scopes_claim`.",
              type = "array",
              elements = { type = "string" },
              required = false,
            },
          },
          {
            channel_token_introspection_scopes_claim = { description = "Use this parameter to specify the claim/property in channel token introspection results (`JSON`) to be verified against values of `config.channel_token_introspection_scopes_required`. This supports nested claims.",
              type = "array",
              elements = { type = "string" },
              default = { "scope" },
              required = false,
            },
          },
          {
            channel_token_introspection_consumer_claim = { description = "When you set a value for this parameter, the plugin tries to map an arbitrary claim specified with this configuration parameter (such as `sub` or `username`) in channel token introspection results to Kong consumer entity", type = "array",
              elements = { type = "string" },
              required = false,
            },
          },
          {
            channel_token_introspection_consumer_by = { description = "When the plugin tries to do channel token introspection results to Kong consumer mapping, it tries to find a matching Kong consumer from properties defined using this configuration parameter. The parameter can take an array of values. Valid values are `id`, `username` and `custom_id`.", type = "array",
              elements = {
                type = "string",
                one_of = { "id", "username", "custom_id" },
              },
              default = { "username", "custom_id" },
              required = false,
            },
          },
          {
            channel_token_introspection_leeway = { description = "You can use this parameter to adjust clock skew between the token issuer introspection results and Kong. The value will be added to introspection results (`JSON`) `exp` claim/property before checking token expiry against Kong servers current time (in seconds). You can disable channel token introspection `expiry` verification altogether with `config.verify_channel_token_introspection_expiry`.", type = "number",
              default = 0,
              required = false,
            },
          },
          {
            channel_token_introspection_timeout = { description = "Timeout in milliseconds for an introspection request. The plugin tries to introspect twice if the first request fails for some reason. If both requests timeout, then the plugin runs two times the `config.access_token_introspection_timeout` on channel token introspection.", type = "number",
              required = false,
            },
          },
          {
            channel_token_signing_algorithm = { description = "When this plugin sets the upstream header as specified with `config.channel_token_upstream_header`, it also re-signs the original channel token using private keys of this plugin. Specify the algorithm that is used to sign the token.", type = "string",
              one_of = {
                "HS256",
                "HS384",
                "HS512",
                "RS256",
                "RS512",
                "ES256",
                "ES384",
                "ES512",
                "PS256",
                "PS384",
                "PS512",
                "EdDSA",
              },
              default = "RS256",
              required = true,
            },
          },
          {
            channel_token_optional = { description = "If a channel token is not provided or no `config.channel_token_request_header` is specified, the plugin cannot verify the channel token. In that case, the plugin normally responds with `401 Unauthorized` (client didn't send a token) or `500 Unexpected` (a configuration error). Enable this parameter to allow the request to proceed even when there is no channel token to check. If the channel token is provided, then this parameter has no effect", type = "boolean",
              default = false,
              required = false,
            },
          },
          {
            verify_channel_token_signature = { description = "Quickly turn on/off the channel token signature verification.", type = "boolean",
              default = true,
              required = false,
            },
          },
          {
            verify_channel_token_expiry = {
              type = "boolean",
              default = true,
              required = false,
            },
          },
          {
            verify_channel_token_scopes = { description = "Quickly turn on/off the channel token required scopes verification specified with `config.channel_token_scopes_required`.", type = "boolean",
              default = true,
              required = false,
            },
          },
          {
            verify_channel_token_introspection_expiry = { description = "Quickly turn on/off the channel token introspection expiry verification.", type = "boolean",
              default = true,
              required = false,
            },
          },
          {
            verify_channel_token_introspection_scopes = { description = "Quickly turn on/off the channel token introspection scopes verification specified with `config.channel_token_introspection_scopes_required`.", type = "boolean",
              default = true,
              required = false,
            },
          },
          {
            cache_channel_token_introspection = { description = "Whether to cache channel token introspection results.", type = "boolean",
              default = true,
              required = false,
            },
          },
          {
            trust_channel_token_introspection = { description = "Providing an opaque channel token for plugin introspection, and verifying expiry and scopes on introspection results may make further payload checks unnecessary before the plugin signs a new token. This also applies when using a JWT token with introspection JSON as per config.channel_token_introspection_jwt_claim. Use this parameter to manage additional payload checks before signing a new token. With true (default), payload's expiry or scopes aren't checked.", type = "boolean",
              default = true,
              required = false,
            },
          },
          {
            enable_channel_token_introspection = { description = "If you don't want to support opaque channel tokens, disable introspection by changing this configuration parameter to `false`.", type = "boolean",
              default = true,
              required = false,
            },
          },
          {
            add_claims = {
              type = "map",
              keys = { type = "string" },
              values = { type = "string" },
              required = false,
              default = {},
              description = "Add customized claims if they are not present yet.",
            },
          },
          {
            set_claims = {
              type = "map",
              keys = { type = "string" },
              values = { type = "string" },
              required = false,
              default = {},
              description = "Set customized claims. If a claim is already present, it will be overwritten.",
            },
          },
        },
      },
    },
  },
}


return config
