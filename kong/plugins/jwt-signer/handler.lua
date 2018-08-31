local BasePlugin = require "kong.plugins.base_plugin"
local responses  = require "kong.tools.responses"
local arguments  = require "kong.plugins.jwt-signer.arguments"
local cache      = require "kong.plugins.jwt-signer.cache"
local log        = require "kong.plugins.jwt-signer.log"
local jwt        = require "kong.openid-connect.jwt"
local jws        = require "kong.openid-connect.jws"
local set        = require "kong.openid-connect.set"


local tonumber   = tonumber
local tostring   = tostring
local ipairs     = ipairs
local concat     = table.concat
local header     = ngx.header
local time       = ngx.time
local type       = type
local var        = ngx.var
local fmt        = string.format


local TOKEN_NAMES = {
  access_token  = "access token",
  channel_token = "channel token",
}


local TOKEN_TYPES = {}
local CONF = {}
local LOGS = {}
local ERRS = {}


do
  local pairs = pairs

  for token_type, token_name in pairs(TOKEN_NAMES) do
    TOKEN_TYPES[#TOKEN_TYPES + 1] = token_type

    CONF[token_type] = {}
    for key, value in pairs {
      issuer                      = "%s_issuer",
      keyset                      = "%s_keyset",
      jwks_uri                    = "%s_jwks_uri",
      request_header              = "%s_request_header",
      leeway                      = "%s_leeway",
      scopes_required             = "%s_scopes_required",
      scopes_claim                = "%s_scopes_claim",
      upstream_header             = "%s_upstream_header",
      upstream_leeway             = "%s_upstream_leeway",
      introspection_endpoint      = "%s_introspection_endpoint",
      introspection_authorization = "%s_introspection_authorization",
      introspection_body_args     = "%s_introspection_body_args",
      introspection_hint          = "%s_introspection_hint",
      introspection_claim         = "%s_introspection_claim",
      signing_algorithm           = "%s_signing_algorithm",
      verify_signature            = "verify_%s_signature",
      verify_expiry               = "verify_%s_expiry",
      verify_scopes               = "verify_%s_scopes",
      cache_introspection         = "cache_%s_introspection",
    } do
      CONF[token_type][key] = fmt(value, token_type)
    end

    LOGS[token_type] = {}
    for key, value in pairs {
      present                     = "%s present",
      jws                         = "%s jws",
      verification                = "%s signature verification",
      jwks                        = "%s jwks could not be loaded",
      jwks_signature              = "%s signature cannot be verified because jwks endpoint was not specified",
      decode                      = "%s could not be decoded",
      opaque                      = "%s opaque",
      introspection_error         = "%s could not be introspected",
      introspection_success       = "%s introspected",
      introspection_claim         = "%s could not be found in introspection claim",
      introspection_claim_decode  = "%s found in introspection claim could not be decoded",
      introspection_endpoint      = "%s could not be instrospected because introspection endpoint was not specified",
      inactive                    = "%s inactive",
      format                      = "%s format not supported",
      payload                     = "%s payload is invalid",
      missing                     = "%s was not found",
      expiring                    = "%s expiry verification",
      expired                     = "%s is expired",
      expiry                      = "%s expiry is mandatory",
      signing                     = "%s signing",
      upstream_header             = "%s upstream header",
      scopes                      = "%s scopes verification",
      no_scopes                   = "%s has no scopes while scopes were required",
      scopes_required             = "%s required scopes",
    } do
      LOGS[token_type][key] = fmt(value, token_name)
    end

    ERRS[token_type] = {}
    for key, value in pairs {
      verification                = "the %s could not be verified",
      invalid                     = "the %s is invalid",
      inactive                    = "the %s inactive",
      expired                     = "the %s expired",
      expiry                      = "the %s has no expiry",
      signing                     = "the %s could not be signed",
    } do
      ERRS[token_type][key] = fmt(value, token_name)
    end

  end
end


local function find_claim(payload, search)
  if type(payload) ~= "table" then
    return nil
  end

  local search_t = type(search)
  local t = payload
  if search_t == "string" then
    if not t[search] then
      return nil
    end

    t = t[search]

  elseif search_t == "table" then
    for _, claim in ipairs(search) do
      if not t[claim] then
        return nil
      end

      t = t[claim]
    end

  else
    return nil
  end

  if type(t) == "table" then
    return concat(t, " ")
  end

  return tostring(t)
end



local function load_keys(...)
  return cache.load_keys(...)
end


local function introspect(...)
  return cache.introspect(...)
end


local function unauthorized(realm, err, desc, real_error)
  if real_error then
    log.notice(real_error)
  end

  header["WWW-Authenticate"] = fmt('Bearer realm="%s", error="%s", error_description="%s"',
                                   realm or var.host,
                                   err,
                                   desc)

  responses.send_HTTP_UNAUTHORIZED()

  return false
end


local function forbidden(realm, err, desc, real_error)
  if real_error then
    log.notice(real_error)
  end

  header["WWW-Authenticate"] = fmt('Bearer realm="%s", error="%s", error_description="%s"',
    realm or var.host,
    err,
    desc)

  responses.send_HTTP_FORBIDDEN("Forbidden")

  return false
end


local function unexpected(realm, err, desc, real_error)
  header["WWW-Authenticate"] = fmt('Bearer realm="%s", error="%s", error_description="%s"',
    realm or var.host,
    err,
    desc)

  responses.send_HTTP_INTERNAL_SERVER_ERROR(real_error)

  return false
end


local JwtSignerHandler = BasePlugin:extend()


function JwtSignerHandler:new()
  JwtSignerHandler.super.new(self, "jwt-signer")
end


function JwtSignerHandler:init_worker()
  JwtSignerHandler.super.init_worker(self)
end


function JwtSignerHandler:access(conf)
  JwtSignerHandler.super.access(self)

  local args = arguments(conf)
  local realm =  args.get_conf_arg("realm")

  for _, token_type in ipairs(TOKEN_TYPES) do

    local config = CONF[token_type]
    local logs   = LOGS[token_type]
    local errs   = ERRS[token_type]

    local err = nil
    local payload

    local request_header = args.get_conf_arg(config.request_header)
    if request_header then
      local request_token = args.get_header(request_header)
      args.clear_header(request_header)

      if request_token then
        log(logs.present)

        local jwt_type = jwt.type(request_token)
        if jwt_type == "JWS" then
          log(logs.jws)

          local token_decoded
          local verify_signature = args.get_conf_arg(config.verify_signature)
          if verify_signature then
            log(logs.verification)

            local jwks_uri = args.get_conf_arg(config.jwks_uri)
            if jwks_uri then
              local public_keys

              public_keys, err = load_keys(jwks_uri)
              if not public_keys then
                log(logs.jwks)
                return unexpected(realm, "unexpected", errs.verification, err)
              end

              token_decoded, err = jws.decode(request_token, { verify_signature = true, keys = public_keys })
            else
              log(logs.jwks_signature)
              return unauthorized(realm,  "invalid_token", errs.verification, err)
            end

          else
            token_decoded, err = jws.decode(request_token, { verify_signature = false })
          end

          if type(token_decoded) ~= "table" then
            log(logs.decode)
            return unauthorized(realm, "invalid_token", errs.verification, err)
          end

          payload = token_decoded.payload

        elseif jwt_type == nil then
          log(logs.opaque)

          local introspection_endpoint = args.get_conf_arg(config.introspection_endpoint)
          if introspection_endpoint then
            local introspection_hint          = args.get_conf_arg(config.introspection_hint)
            local introspection_authorization = args.get_conf_arg(config.introspection_authorization)
            local introspection_body_args     = args.get_conf_arg(config.introspection_body_args)
            local cache_introspection         = args.get_conf_arg(config.cache_introspection)

            local token_info
            token_info, err = introspect(introspection_endpoint,
                                         request_token,
                                         introspection_hint,
                                         introspection_authorization,
                                         introspection_body_args,
                                         cache_introspection)

            if type(token_info) ~= "table" then
              log(logs.introspection_error)
              return unauthorized(realm, "invalid_token", errs.invalid, err)
            end

            log(logs.introspection_success)

            if token_info.active == true then
              local introspection_claim = args.get_conf_arg(config.introspection_claim)
              if introspection_claim then
                local token_in_claim = find_claim(token_info, introspection_claim)
                if not token_in_claim then
                  log(logs.introspection_claim)
                  return unauthorized(realm, "invalid_token", errs.invalid, err)
                end

                local token_decoded
                token_decoded, err = jws.decode(token_in_claim, { verify_signature = false })

                if type(token_decoded) ~= "table" then
                  log(logs.introspection_claim_decode)
                  return unauthorized(realm, "invalid_token", errs.invalid, err)
                end

                payload = token_decoded.payload

              else
                token_info.active = nil
                payload = token_info
              end

            else
              return unauthorized(realm, "invalid_token", errs.inactive, logs.inactive)
            end

          else
            return unexpected(realm, "unexpected", "the introspection endpoint was not specified",
                              logs.introspection_endpoint)
          end

        else
          log(logs.format)
          return unauthorized(realm, "invalid_token", errs.invalid, err)
        end

        if type(payload) ~= "table" then
          log(logs.payload)
          return unauthorized(realm, "invalid_token", errs.invalid, err)
        end

      else
        log(logs.missing)
        return unauthorized(realm, "invalid_token", errs.invalid, err)
      end
    end

    if payload then
      local expiry

      local verify_expiry = args.get_conf_arg(config.verify_expiry)
      if verify_expiry then
        log(logs.expiring)

        local leeway = args.get_conf_arg(config.leeway, 0)

        expiry = tonumber(payload.exp)
        if expiry then
          if time() > (expiry + leeway) then
            return unauthorized(realm, "invalid_token", errs.expired, logs.expired)
          end

        else
          return unauthorized(realm, "invalid_token", errs.expiry, logs.expiry)
        end
      end

      local verify_scopes = args.get_conf_arg(config.verify_scopes)
      if verify_scopes then
        log(logs.scopes)

        local scopes_required = args.get_conf_arg(config.scopes_required)
        if scopes_required then
          local scopes_claim = args.get_conf_arg(config.scopes_claim, { "scope" })

          local scopes = find_claim(payload, scopes_claim)
          if not scopes then
            return forbidden(realm, "invalid_token", errs.invalid, logs.no_scopes)
          end

          scopes = set.new(scopes)

          local scopes_valid
          for _, scope_required in ipairs(scopes_required) do
            if set.has(scope_required, scopes) then
              scopes_valid = true
              break
            end
          end

          if not scopes_valid then
            local real_err = fmt(logs.scopes_required .. " [ %s ] were not found [ %s ]",
                                 concat(scopes_required, ", "), concat(scopes, ", "))

            return forbidden(realm, "invalid_token", errs.invalid, real_err)
          end
        end
      end

      local upstream_header = args.get_conf_arg(config.upstream_header)
      if upstream_header then
        log(logs.signing)

        local issuer = args.get_conf_arg(config.issuer)
        if issuer then
          payload.original_iss = payload.iss
          payload.iss = issuer
        end

        local upstream_leeway = args.get_conf_arg(config.upstream_leeway, 0)
        if upstream_leeway ~= 0 then
          payload.original_exp = expiry or tonumber(payload.exp)
          payload.exp = expiry + upstream_leeway
        end

        local keyset = args.get_conf_arg(config.keyset, "kong")
        local private_keys
        private_keys, err = load_keys(keyset)
        if not private_keys then
          return unexpected(realm, "unexpected", "the keys could not be loaded", err)
        end

        local signing_algorithm = args.get_conf_arg(config.signing_algorithm)
        local jwk = private_keys[signing_algorithm]

        if not jwk then
          return unexpected(realm, "unexpected", "the key could not be found", "signing algorithm was not found")
        end

        local signed_token
        signed_token, err = jws.encode({
          payload = payload,
          jwk     = jwk,
        })

        if not signed_token then
          return unexpected(realm, "invalid_token", errs.signing, err)
        end

        log(logs.upstream_header)

        args.set_header(upstream_header, signed_token)
      end
    end
  end
end


JwtSignerHandler.PRIORITY = 802
JwtSignerHandler.VERSION  = "0.0.5"


return JwtSignerHandler

