local arguments = require "kong.plugins.jwt-signer.arguments"
local cache     = require "kong.plugins.jwt-signer.cache"
local log       = require "kong.plugins.jwt-signer.log"
local errors    = require "kong.dao.errors"


local get_phase = ngx.get_phase


local function self_check(_, conf)
  local phase = get_phase()
  if phase == "access" or phase == "content" then
    local args = arguments(conf)

    local access_token_jwks_uri = args.get_conf_arg("access_token_jwks_uri")
    if access_token_jwks_uri then
      local ok, err = cache.load_keys(access_token_jwks_uri)
      if not ok then
        log.notice("unable to load access token jwks (", err, ")")
        return false, errors.schema("unable to load access token jwks")
      end
    end

    local channel_token_jwks_uri = args.get_conf_arg("channel_token_jwks_uri")
    if channel_token_jwks_uri then
      local ok, err = cache.load_keys(channel_token_jwks_uri)
      if not ok then
        log.notice("unable to load channel token jwks (", err, ")")
        return false, errors.schema("unable to load channel token jwks")
      end
    end

    local access_token_keyset = args.get_conf_arg("access_token_keyset")
    if access_token_keyset then
      local ok, err = cache.load_keys(access_token_keyset)
      if not ok then
        log.notice("unable to load access token keyset (", err, ")")
        return false, errors.schema("unable to load access token keyset")
      end
    end

    local channel_token_keyset = args.get_conf_arg("channel_token_keyset")
    if channel_token_keyset and channel_token_keyset ~= access_token_keyset then
      local ok, err = cache.load_keys(channel_token_keyset)
      if not ok then
        log.notice("unable to load channel token keyset (", err, ")")
        return false, errors.schema("unable to load channel token keyset")
      end
    end

    if access_token_keyset ~= "kong" and channel_token_keyset ~= "kong" then
      local ok, err = cache.load_keys("kong")
      if not ok then
        log.notice("unable to load kong keyset (", err, ")")
        return false, errors.schema("unable to load kong keyset")
      end
    end
  end

  return true
end


return {
  no_consumer                                   = true,
  self_check                                    = self_check,
  fields                                        = {
    realm                                       = {
      required                                  = false,
      type                                      = "string",
    },
    enable_instrumentation                      = {
      required                                  = false,
      type                                      = "boolean",
      default                                   = false,
    },
    access_token_issuer                         = {
      required                                  = false,
      type                                      = "string",
      default                                   = "kong"
    },
    access_token_keyset                         = {
      required                                  = false,
      type                                      = "string",
      default                                   = "kong"
    },
    access_token_jwks_uri                       = {
      required                                  = false,
      type                                      = "url",
    },
    access_token_request_header                 = {
      required                                  = false,
      type                                      = "string",
      default                                   = "Authorization",
    },
    access_token_leeway                         = {
      required                                  = false,
      type                                      = "number",
      default                                   = 0,
    },
    access_token_scopes_required                = {
      required                                  = false,
      type                                      = "array",
    },
    access_token_scopes_claim                   = {
      required                                  = true,
      type                                      = "array",
      default                                   = {
        "scope"
      },
    },
    access_token_consumer_claim                 = {
      required                                  = false,
      type                                      = "array",
    },
    access_token_consumer_by                    = {
      required                                  = false,
      type                                      = "array",
      enum                                      = {
        "id",
        "username",
        "custom_id",
      },
      default                                   = {
        "username",
        "custom_id",
      },
    },
    access_token_upstream_header                = {
      required                                  = false,
      type                                      = "string",
      default                                   = "Authorization",
    },
    access_token_upstream_leeway                = {
      required                                  = false,
      type                                      = "number",
      default                                   = 0,
    },
    access_token_introspection_endpoint         = {
      required                                  = false,
      type                                      = "url",
    },
    access_token_introspection_authorization    = {
      required                                  = false,
      type                                      = "string",
    },
    access_token_introspection_body_args        = {
      required                                  = false,
      type                                      = "string",
    },
    access_token_introspection_hint             = {
      required                                  = false,
      type                                      = "string",
      default                                   = "access_token",
    },
    access_token_introspection_jwt_claim        = {
      required                                  = false,
      type                                      = "array",
    },
    access_token_introspection_scopes_required  = {
      required                                  = false,
      type                                      = "array",
    },
    access_token_introspection_scopes_claim     = {
      required                                  = true,
      type                                      = "array",
      default                                   = {
        "scope"
      },
    },
    access_token_introspection_consumer_claim   = {
      required                                  = false,
      type                                      = "array",
    },
    access_token_introspection_consumer_by      = {
      required                                  = false,
      type                                      = "array",
      enum                                      = {
        "id",
        "username",
        "custom_id",
      },
      default                                   = {
        "username",
        "custom_id",
      },
    },
    access_token_introspection_leeway           = {
      required                                  = false,
      type                                      = "number",
      default                                   = 0,
    },
    access_token_introspection_timeout          = {
      required                                  = false,
      type                                      = "number",
    },
    access_token_signing_algorithm              = {
      required                                  = true,
      type                                      = "string",
      enum = {
        "RS256",
        "RS512",
      },
      default                                   = "RS256",
    },
    access_token_optional                       = {
      required                                  = false,
      type                                      = "boolean",
      default                                   = false,
    },
    verify_access_token_signature               = {
      required                                  = false,
      type                                      = "boolean",
      default                                   = true,
    },
    verify_access_token_expiry                  = {
      required                                  = false,
      type                                      = "boolean",
      default                                   = true,
    },
    verify_access_token_scopes                  = {
      required                                  = false,
      type                                      = "boolean",
      default                                   = true,
    },
    verify_access_token_introspection_expiry    = {
      required                                  = false,
      type                                      = "boolean",
      default                                   = true,
    },
    verify_access_token_introspection_scopes    = {
      required                                  = false,
      type                                      = "boolean",
      default                                   = true,
    },
    cache_access_token_introspection            = {
      required                                  = false,
      type                                      = "boolean",
      default                                   = true,
    },
    trust_access_token_introspection            = {
      required                                  = false,
      type                                      = "boolean",
      default                                   = true,
    },
    enable_access_token_introspection           = {
      required                                  = false,
      type                                      = "boolean",
      default                                   = true,
    },
    channel_token_issuer                        = {
      required                                  = false,
      type                                      = "string",
      default                                   = "kong"
    },
    channel_token_keyset                        = {
      required                                  = false,
      type                                      = "string",
      default                                   = "kong"
    },
    channel_token_jwks_uri                      = {
      required                                  = false,
      type                                      = "url",
    },
    channel_token_request_header                = {
      required                                  = false,
      type                                      = "string",
    },
    channel_token_leeway                        = {
      required                                  = false,
      type                                      = "number",
      default                                   = 0,
    },
    channel_token_scopes_required               = {
      required                                  = false,
      type                                      = "array",
    },
    channel_token_scopes_claim                  = {
      required                                  = false,
      type                                      = "array",
      default                                   = {
        "scope"
      },
    },
    channel_token_consumer_claim                = {
      required                                  = false,
      type                                      = "array",
    },
    channel_token_consumer_by                   = {
      required                                  = false,
      type                                      = "array",
      enum                                      = {
        "id",
        "username",
        "custom_id",
      },
      default                                   = {
        "username",
        "custom_id",
      },
    },
    channel_token_upstream_header               = {
      required                                  = false,
      type                                      = "string",
    },
    channel_token_upstream_leeway               = {
      required                                  = false,
      type                                      = "number",
      default                                   = 0,
    },
    channel_token_introspection_endpoint        = {
      required                                  = false,
      type                                      = "url",
    },
    channel_token_introspection_authorization   = {
      required                                  = false,
      type                                      = "string",
    },
    channel_token_introspection_body_args       = {
      required                                  = false,
      type                                      = "string",
    },
    channel_token_introspection_hint            = {
      required                                  = false,
      type                                      = "string",
    },
    channel_token_introspection_jwt_claim       = {
      required                                  = false,
      type                                      = "array",
    },
    channel_token_introspection_scopes_required = {
      required                                  = false,
      type                                      = "array",
    },
    channel_token_introspection_scopes_claim    = {
      required                                  = false,
      type                                      = "array",
      default                                   = {
        "scope"
      },
    },
    channel_token_introspection_consumer_claim  = {
      required                                  = false,
      type                                      = "array",
    },
    channel_token_introspection_consumer_by     = {
      required                                  = false,
      type                                      = "array",
      enum                                      = {
        "id",
        "username",
        "custom_id",
      },
      default                                   = {
        "username",
        "custom_id",
      },
    },
    channel_token_introspection_leeway          = {
      required                                  = false,
      type                                      = "number",
      default                                   = 0,
    },
    channel_token_introspection_timeout         = {
      required                                  = false,
      type                                      = "number",
    },
    channel_token_signing_algorithm             = {
      required                                  = true,
      type                                      = "string",
      enum = {
        "RS256",
        "RS512",
      },
      default                                   = "RS256",
    },
    channel_token_optional                      = {
      required                                  = false,
      type                                      = "boolean",
      default                                   = false,
    },
    verify_channel_token_signature              = {
      required                                  = false,
      type                                      = "boolean",
      default                                   = true,
    },
    verify_channel_token_expiry                 = {
      required                                  = false,
      type                                      = "boolean",
      default                                   = true,
    },
    verify_channel_token_scopes                 = {
      required                                  = false,
      type                                      = "boolean",
      default                                   = true,
    },
    verify_channel_token_introspection_expiry   = {
      required                                  = false,
      type                                      = "boolean",
      default                                   = true,
    },
    verify_channel_token_introspection_scopes   = {
      required                                  = false,
      type                                      = "boolean",
      default                                   = true,
    },
    cache_channel_token_introspection           = {
      required                                  = false,
      type                                      = "boolean",
      default                                   = true,
    },
    trust_channel_token_introspection           = {
      required                                  = false,
      type                                      = "boolean",
      default                                   = true,
    },
    enable_channel_token_introspection          = {
      required                                  = false,
      type                                      = "boolean",
      default                                   = true,
    },
  },
}
