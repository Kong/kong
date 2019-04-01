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

return {
  name = "jwt-signer",
  fields = {
    { consumer  = typedefs.no_consumer  },
    { run_on    = typedefs.run_on_first },
    { config    = {
        type                = "record",
        custom_validator    = validate_tokens,
        fields              = {
          {
            realm = {
              type = "string",
              required = false,
            },
          },
          {
            enable_instrumentation = {
              type = "boolean",
              default = false,
              required = false,
            },
          },
          {
            access_token_issuer = {
              type = "string",
              default = "kong",
              required = false,
            },
          },
          {
            access_token_keyset = {
              type = "string",
              default = "kong",
              required = false,
            },
          },
          {
            access_token_jwks_uri = typedefs.url {
              required = false,
            },
          },
          {
            access_token_request_header = {
              type = "string",
              default = "Authorization",
              required = false,
            },
          },
          {
            access_token_leeway = {
              type = "number",
              default =  0,
              required = false,
            },
          },
          {
            access_token_scopes_required = {
              type = "array",
              elements = { type = "string" },
              required = false,
            },
          },
          {
            access_token_scopes_claim = {
              type = "array",
              elements = { type = "string" },
              default = { "scope" },
              required = false,
            },
          },
          {
            access_token_consumer_claim = {
              type = "array",
              elements = { type = "string" },
              required = false,
            },
          },
          {
            access_token_consumer_by = {
              type = "array",
              elements = {
                type = "string",
                one_of = {"id", "username", "custom_id" },
              },
              default = { "username", "custom_id" },
              required = false,
            },
          },
          {
            access_token_upstream_header = {
              type = "string",
              default = "Authorization:Bearer",
              required = false,
            },
          },
          {
            access_token_upstream_leeway = {
              type = "number",
              default = 0,
              required = false,
            },
          },
          {
            access_token_introspection_endpoint = typedefs.url {
              required = false,
            },
          },
          {
            access_token_introspection_endpoint = typedefs.url {
              required = false,
            },
          },
          {
            access_token_introspection_authorization = {
              type = "string",
              required = false,
            },
          },
          {
            access_token_introspection_body_args = {
              type = "string",
              required = false,
            },
          },
          {
            access_token_introspection_hint = {
              type = "string",
              default = "access_token",
              required = false,
            },
          },
          {
            access_token_introspection_jwt_claim = {
              type = "array",
              elements = { type = "string" },
              required = false,
            },
          },
          {
            access_token_introspection_scopes_required = {
              type = "array",
              elements = { type = "string" },
              required =  false,
            },
          },
          {
            access_token_introspection_scopes_claim = {
              type = "array",
              elements = { type = "string" },
              default = { "scope" },
              required = true,
            },
          },
          {
            access_token_introspection_consumer_claim = {
              type = "array",
              elements = { type = "string" },
              required = false,
            },
          },
          {
            access_token_introspection_consumer_by = {
              type = "array",
              elements = {
                type = "string",
                one_of = { "id",  "username", "custom_id" },
              },
              default = { "username", "custom_id" },
              required = false,
            },
          },
          {
            access_token_introspection_leeway = {
              type = "number",
              default = 0,
              required = false,
            },
          },
          {
            access_token_introspection_timeout = {
              type = "number",
              required = false,
            },
          },
          {
            access_token_signing_algorithm = {
              type = "string",
              one_of = { "RS256", "RS512" },
              default = "RS256",
              required = true,
            },
          },
          {
            access_token_optional = {
              type = "boolean",
              default = false,
              required = false,
            },
          },
          {
            verify_access_token_signature = {
              type = "boolean",
              default = true,
              required = false,
            },
          },
          {
            verify_access_token_expiry = {
              type = "boolean",
              default = true,
              required = false,
            },
          },
          {
            verify_access_token_scopes = {
              type = "boolean",
              default = true,
              required = false,
            },
          },
          {
            verify_access_token_introspection_expiry = {
              type = "boolean",
              default = true,
              required = false,
            },
          },
          {
            verify_access_token_introspection_scopes = {
              type = "boolean",
              default = true,
              required = false,
            },
          },
          {
            cache_access_token_introspection = {
              type = "boolean",
              default = true,
              required = false,
            },
          },
          {
            trust_access_token_introspection = {
              type = "boolean",
              default = true,
              required = false,
            },
          },
          {
            enable_access_token_introspection = {
              type = "boolean",
              default = true,
              required =  false,
            },
          },
          {
            channel_token_issuer = {
              type = "string",
              default = "kong",
              required = false,
            },
          },
          {
            channel_token_keyset = {
              type = "string",
              default = "kong",
              required = false,
            },
          },
          {
            channel_token_jwks_uri = typedefs.url {
              required = false,
            },
          },
          {
            channel_token_request_header = {
              type = "string",
              required = false,
            },
          },
          {
            channel_token_leeway = {
              type = "number",
              default = 0,
              required = false,
            },
          },
          {
            channel_token_scopes_required = {
              type = "array",
              elements = { type = "string" },
              required = false,
            },
          },
          {
            channel_token_scopes_claim = {
              type = "array",
              elements = { type = "string" },
              default = { "scope" },
              required = false,
            },
          },
          {
            channel_token_consumer_claim = {
              type = "array",
              elements = { type = "string" },
              required = false,
            },
          },
          {
            channel_token_consumer_by = {
              type = "array",
              elements = {
                type = "string",
                one_of = { "id", "username", "custom_id" },
              },
              default =  { "username", "custom_id" },
            },
          },
          {
            channel_token_upstream_header = {
              type = "string",
              required = false,
            },
          },
          {
            channel_token_upstream_leeway = {
              type = "number",
              default = 0,
              required = false,
            },
          },
          {
            channel_token_introspection_endpoint = typedefs.url {
              required = false,
            },
          },
          {
            channel_token_introspection_authorization   = {
              type = "string",
              elements = { type = "string" },
              required = false,
            },
          },
          {
            channel_token_introspection_body_args = {
              type = "string",
              elements = { type = "string" },
              required = false,
            },
          },
          {
            channel_token_introspection_hint = {
              type = "string",
              elements = { type = "string" },
              required = false,
            },
          },
          {
            channel_token_introspection_jwt_claim = {
              type = "array",
              elements = { type = "string" },
              required = false,
            },
          },
          {
            channel_token_introspection_scopes_required = {
              type = "array",
              elements = { type = "string" },
              required = false,
            },
          },
          {
            channel_token_introspection_scopes_claim = {
              type = "array",
              elements = { type = "string" },
              default = { "scope" },
              required = false,
            },
          },
          {
            channel_token_introspection_consumer_claim = {
              type = "array",
              elements = { type = "string" },
              required = false,
            },
          },
          {
            channel_token_introspection_consumer_by = {
              type = "array",
              elements = {
                type = "string",
                one_of = { "id", "username", "custom_id" },
              },
              default = { "username", "custom_id" },
              required = false,
            },
          },
          {
            channel_token_introspection_leeway = {
              type = "number",
              default = 0,
              required = false,
            },
          },
          {
            channel_token_introspection_timeout = {
              type = "number",
              required = false,
            },
          },
          {
            channel_token_signing_algorithm = {
              type = "string",
              one_of = { "RS256", "RS512" },
              default = "RS256",
              required = true,
            },
          },
          {
            channel_token_optional = {
              type = "boolean",
              default = false,
              required = false,
            },
          },
          {
            verify_channel_token_signature = {
              type = "boolean",
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
            verify_channel_token_scopes = {
              type = "boolean",
              default = true,
              required = false,
            },
          },
          {
            verify_channel_token_introspection_expiry = {
              type = "boolean",
              default = true,
              required = false,
            },
          },
          {
            verify_channel_token_introspection_scopes = {
              type = "boolean",
              default = true,
              required = false,
            },
          },
          {
            cache_channel_token_introspection = {
              type = "boolean",
              default = true,
              required = false,
            },
          },
          {
            trust_channel_token_introspection = {
              type = "boolean",
              default = true,
              required = false,
            },
          },
          {
            enable_channel_token_introspection = {
              type = "boolean",
              default = true,
              required = false,
            },
          },
        },
      },
    },
  },
}
