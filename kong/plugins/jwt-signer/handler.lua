local BasePlugin = require "kong.plugins.base_plugin"
local constants  = require "kong.constants"
local responses  = require "kong.tools.responses"
local arguments  = require "kong.plugins.jwt-signer.arguments"
local cache      = require "kong.plugins.jwt-signer.cache"
local log        = require "kong.plugins.jwt-signer.log"
local jwt        = require "kong.openid-connect.jwt"
local jws        = require "kong.openid-connect.jws"
local set        = require "kong.openid-connect.set"

local ngx        = ngx
local tonumber   = tonumber
local tostring   = tostring
local ipairs     = ipairs
local concat     = table.concat
local header     = ngx.header
local lower      = string.lower
local time       = ngx.time
local type       = type
local var        = ngx.var
local sub        = string.sub
local fmt        = string.format


local TOKEN_TYPES = {
  "access_token",
  "channel_token",
}

local TOKEN_NAMES = {
  access_token  = "access token",
  channel_token = "channel token",
}


local TOKEN_COUNT = #TOKEN_TYPES


local CONF = {}
local LOGS = {}
local ERRS = {}


do
  local pairs = pairs

  for i = 1, TOKEN_COUNT do
    local token_type = TOKEN_TYPES[i]
    local token_name = TOKEN_NAMES[token_type]

    CONF[token_type] = {}
    for key, value in pairs {
      issuer                         = "%s_issuer",
      keyset                         = "%s_keyset",
      jwks_uri                       = "%s_jwks_uri",
      request_header                 = "%s_request_header",
      leeway                         = "%s_leeway",
      scopes_required                = "%s_scopes_required",
      scopes_claim                   = "%s_scopes_claim",
      consumer_claim                 = "%s_consumer_claim",
      consumer_by                    = "%s_consumer_by",
      upstream_header                = "%s_upstream_header",
      upstream_leeway                = "%s_upstream_leeway",
      introspection_endpoint         = "%s_introspection_endpoint",
      introspection_authorization    = "%s_introspection_authorization",
      introspection_body_args        = "%s_introspection_body_args",
      introspection_hint             = "%s_introspection_hint",
      introspection_jwt_claim        = "%s_introspection_jwt_claim",
      introspection_consumer_claim   = "%s_introspection_consumer_claim",
      introspection_consumer_by      = "%s_introspection_consumer_by",
      introspection_scopes_required  = "%s_introspection_scopes_required",
      introspection_scopes_claim     = "%s_introspection_scopes_claim",
      introspection_leeway           = "%s_introspection_leeway",
      introspection_timeout          = "%s_introspection_timeout",
      signing_algorithm              = "%s_signing_algorithm",
      optional                       = "%s_optional",
      verify_signature               = "verify_%s_signature",
      verify_expiry                  = "verify_%s_expiry",
      verify_scopes                  = "verify_%s_scopes",
      verify_introspection_expiry    = "verify_%s_introspection_expiry",
      verify_introspection_scopes    = "verify_%s_introspection_scopes",
      cache_introspection            = "cache_%s_introspection",
      trust_introspection            = "trust_%s_introspection",
      enable_introspection           = "enable_%s_introspection",
    } do
      CONF[token_type][key] = fmt(value, token_type)
    end

    LOGS[token_type] = {}
    for key, value in pairs {
      present                        = "%s present",
      jws                            = "%s jws",
      verification                   = "%s signature verification",
      jwks                           = "%s jwks could not be loaded",
      jwks_signature                 = "%s signature cannot be verified because jwks endpoint was not specified",
      decode                         = "%s could not be decoded",
      opaque                         = "%s opaque",
      introspection_error            = "%s could not be introspected",
      introspection_success          = "%s introspected",
      introspection_jwt_claim        = "%s could not be found in introspection jwt claim",
      introspection_jwt_claim_decode = "%s found in introspection jwt claim could not be decoded",
      introspection_endpoint         = "%s could not be instrospected because introspection endpoint was not specified",
      inactive                       = "%s inactive",
      format                         = "%s format not supported",
      payload                        = "%s payload is invalid",
      missing                        = "%s was not found",
      no_header                      = "%s cannot be found because the name of the header was not specified",
      expiring                       = "%s expiry verification",
      expired                        = "%s is expired",
      expiry                         = "%s expiry is mandatory",
      introspection_expiring         = "%s introspection expiry verification",
      introspection_expired          = "%s introspection expired",
      introspection_expiry           = "%s introspection expiry is mandatory",
      introspection_scopes_claim     = "%s introspection scopes claim was not specified",
      introspection_consumer_by      = "%s introspection consumer search order was not specified",
      introspection_consumer_claim   = "%s introspection consumer claim could not be found",
      introspection_consumer         = "%s introspection consumer could not be found for ",
      introspection_disabled         = "%s introspection is disabled",
      consumer_by                    = "%s consumer search order was not specified",
      consumer_claim                 = "%s consumer claim could not be found",
      consumer                       = "%s consumer could not be found for ",
      scopes_claim                   = "%s scopes claim was not specified",
      signing                        = "%s signing",
      upstream_header                = "%s upstream header",
      scopes                         = "%s scopes verification",
      no_scopes                      = "%s has no scopes while scopes were required",
      scopes_required                = "%s required scopes",
      introspection_scopes           = "%s introspection scopes verification",
      no_introspection_scopes        = "%s has no introspection scopes while scopes were required",
      introspection_scopes_required  = "%s required introspection scopes",
      key_not_found                  = "%s signing key for a requested signing algorithm was not found",
      optional                       = "%s was not found (optional)",
    } do
      LOGS[token_type][key] = fmt(value, token_name)
    end

    ERRS[token_type] = {}
    for key, value in pairs {
      verification                   = "the %s could not be verified",
      invalid                        = "the %s is invalid",
      inactive                       = "the %s inactive",
      no_header                      = "the %s header name was not configured",
      expired                        = "the %s expired",
      expiry                         = "the %s has no expiry",
      introspection_endpoint         = "the %s introspection endpoint was not specified",
      introspection_expired          = "the %s introspection expired",
      introspection_expiry           = "the %s introspection has no expiry",
      introspection_scopes_claim     = "the %s introspection scopes claim was not specified",
      introspection_consumer_by      = "the %s introspection consumer search order was not specified",
      consumer_by                    = "the %s consumer search order was not specified",
      scopes_claim                   = "the %s scopes claim was not specified",
      signing                        = "the %s could not be signed",
      keys_load                      = "the %s signing keyset could not be loaded",
      key_not_found                  = "the %s signing key could not be found"
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


local function load_consumer(...)
  return cache.load_consumer(...)
end


local function unauthorized(realm, err, desc, real_error, ...)
  if real_error then
    log.notice(real_error, ...)
  end

  header["WWW-Authenticate"] = fmt('Bearer realm="%s", error="%s", error_description="%s"',
                                   realm or var.host,
                                   err,
                                   desc)

  responses.send_HTTP_UNAUTHORIZED()

  return false
end


local function forbidden(realm, err, desc, real_error, ...)
  if real_error then
    log.notice(real_error, ...)
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


local function noop()
end


local function instrument()
  local updated_now = function()
    ngx.update_time()
    return ngx.now()
  end
  local worker  = ngx.worker.id()
  local request = ngx.var.request_id
  local started = updated_now()
  local elapsed = function()
    return fmt("%.3f" , updated_now() - started)
  end
  return function(...)
    log.crit("[elapsed: ", elapsed(), "] [request: ", request, "] [worker: ", worker, "] ", ...)
  end
end


local JwtSignerHandler = BasePlugin:extend()


function JwtSignerHandler:new()
  JwtSignerHandler.super.new(self, "jwt-signer")
end


function JwtSignerHandler:init_worker()
  JwtSignerHandler.super.init_worker(self)
  cache.init_worker()
end


function JwtSignerHandler:access(conf)
  JwtSignerHandler.super.access(self)

  local args = arguments(conf)
  local ins = args.get_conf_arg("enable_instrumentation") and instrument() or noop

  ins("request started")

  local realm = args.get_conf_arg("realm")
  local consumer

  for i = 1, TOKEN_COUNT do
    local token_type = TOKEN_TYPES[i]

    local config = CONF[token_type]
    local logs   = LOGS[token_type]
    local errs   = ERRS[token_type]

    local err = nil
    local enable_introspection = nil
    local trust_introspection = nil
    local payload

    local request_header = args.get_conf_arg(config.request_header)
    if request_header then
      local request_token = args.get_header(request_header)

      args.clear_header(request_header)

      if request_token then
        log(logs.present)
        ins(logs.present)

        local request_token_prefix = lower(sub(request_token, 1, 6))
        if request_token_prefix == "bearer" then
          request_token = sub(request_token, 8)

        elseif sub(request_token_prefix, 1, 5) == "basic" then
          request_token = sub(request_token, 7)
        end

        local jwt_type = jwt.type(request_token)
        if jwt_type == "JWS" then
          log(logs.jws)
          ins(logs.jws)

          local token_decoded
          local verify_signature = args.get_conf_arg(config.verify_signature)
          if verify_signature then
            log(logs.verification)
            ins(logs.verification)

            local jwks_uri = args.get_conf_arg(config.jwks_uri)
            if jwks_uri then
              local public_keys
              public_keys, err = load_keys(jwks_uri)
              if not public_keys then
                log(logs.jwks)
                ins(logs.jwks)
                return unexpected(realm, "unexpected", errs.verification, err)
              end

              token_decoded, err = jws.decode(request_token, { verify_signature = true, keys = public_keys })
            else
              log(logs.jwks_signature)
              ins(logs.jwks_signature)
              return unauthorized(realm,  "invalid_token", errs.verification, err)
            end

          else
            token_decoded, err = jws.decode(request_token, { verify_signature = false })
          end

          if type(token_decoded) ~= "table" then
            log(logs.decode)
            ins(logs.decode)
            return unauthorized(realm, "invalid_token", errs.verification, err)
          end

          payload = token_decoded.payload

        elseif jwt_type == nil then
          log(logs.opaque)
          ins(logs.opaque)

          enable_introspection = args.get_conf_arg(config.enable_introspection)

          if enable_introspection then
            trust_introspection  = args.get_conf_arg(config.trust_introspection)

            local introspection_endpoint = args.get_conf_arg(config.introspection_endpoint)
            if introspection_endpoint then
              local introspection_hint          = args.get_conf_arg(config.introspection_hint)
              local introspection_authorization = args.get_conf_arg(config.introspection_authorization)
              local introspection_body_args     = args.get_conf_arg(config.introspection_body_args)
              local introspection_timeout       = args.get_conf_arg(config.introspection_timeout)
              local cache_introspection         = args.get_conf_arg(config.cache_introspection)

              local token_info
              token_info, err = introspect(introspection_endpoint,
                                           request_token,
                                           introspection_hint,
                                           introspection_authorization,
                                           introspection_body_args,
                                           cache_introspection,
                                           introspection_timeout)

              if type(token_info) ~= "table" then
                log(logs.introspection_error)
                ins(logs.introspection_error)
                return unauthorized(realm, "invalid_token", errs.invalid, err)
              end

              log(logs.introspection_success)
              ins(logs.introspection_success)

              if token_info.active == true then
                local verify_introspection_expiry = args.get_conf_arg(config.verify_introspection_expiry)
                if verify_introspection_expiry then
                  log(logs.introspection_expiring)
                  ins(logs.introspection_expiring)

                  local introspection_leeway = args.get_conf_arg(config.introspection_leeway, 0)

                  local introspection_expiry = tonumber(token_info.exp)
                  if introspection_expiry then
                    if time() > (introspection_expiry + introspection_leeway) then
                      ins(logs.introspection_expired)
                      return unauthorized(realm, "invalid_token", errs.introspection_expired, logs.introspection_expired)
                    end

                  else
                    ins(logs.introspection_expiry)
                    return unauthorized(realm, "invalid_token", errs.introspection_expiry, logs.introspection_expiry)
                  end
                end

                local introspection_jwt_claim = args.get_conf_arg(config.introspection_jwt_claim)
                if introspection_jwt_claim then
                  local jwt_in_claim = find_claim(token_info, introspection_jwt_claim)
                  if not jwt_in_claim then
                    ins(logs.introspection_jwt_claim)
                    return unauthorized(realm, "invalid_token", errs.invalid, logs.introspection_jwt_claim)
                  end

                  local token_decoded
                  token_decoded, err = jws.decode(jwt_in_claim, { verify_signature = false })

                  if type(token_decoded) ~= "table" then
                    log(logs.introspection_jwt_claim_decode)
                    ins(logs.introspection_jwt_claim_decode)
                    return unauthorized(realm, "invalid_token", errs.invalid, err)
                  end

                  payload = token_decoded.payload

                else
                  token_info.active = nil
                  payload = token_info
                end

                local verify_introspection_scopes = args.get_conf_arg(config.verify_introspection_scopes)
                if verify_introspection_scopes then
                  log(logs.introspection_scopes)
                  ins(logs.introspection_scopes)

                  local introspection_scopes_required = args.get_conf_arg(config.introspection_scopes_required)
                  if introspection_scopes_required then
                    local introspection_scopes_claim = args.get_conf_arg(config.introspection_scopes_claim)
                    if not introspection_scopes_claim then
                      ins(logs.introspection_scopes_claim)
                      return unexpected(realm, "unexpected", errs.introspection_scopes_claim,
                                                             logs.introspection_scopes_claim)
                    end

                    local introspection_scopes = find_claim(token_info, introspection_scopes_claim)
                    if not introspection_scopes then
                      ins(logs.no_introspection_scopes)
                      return forbidden(realm, "invalid_token", errs.invalid, logs.no_introspection_scopes)
                    end

                    introspection_scopes = set.new(introspection_scopes)

                    local introspection_scopes_valid
                    for _, introspection_scope_required in ipairs(introspection_scopes_required) do
                      if set.has(introspection_scope_required, introspection_scopes) then
                        introspection_scopes_valid = true
                        break
                      end
                    end

                    if not introspection_scopes_valid then
                      local real_err = fmt(logs.introspection_scopes_required .. " [ %s ] were not found [ %s ]",
                        concat(introspection_scopes_required, ", "), concat(introspection_scopes, ", "))

                      ins(real_err)
                      return forbidden(realm, "invalid_token", errs.invalid, real_err)
                    end
                  end
                end

                if not consumer then
                  local introspection_consumer_claim = args.get_conf_arg(config.introspection_consumer_claim)
                  if introspection_consumer_claim then
                    local introspection_consumer_by = args.get_conf_arg(config.introspection_consumer_by)
                    if not introspection_consumer_by then
                      ins(introspection_consumer_by)
                      return unexpected(realm, "unexpected", errs.introspection_consumer_by,
                                                             logs.introspection_consumer_by)
                    end

                    local introspection_consumer = find_claim(token_info, introspection_consumer_claim)
                    if not introspection_consumer then
                      ins(introspection_consumer_claim)
                      return forbidden(realm, "invalid_token", errs.invalid, logs.introspection_consumer_claim)
                    end

                    consumer, err = load_consumer(introspection_consumer, introspection_consumer_by)
                    if not consumer then
                      log(logs.introspection_consumer, introspection_consumer)
                      ins(logs.introspection_consumer, introspection_consumer)
                      return forbidden(realm, "invalid_token", errs.invalid, err)
                    end
                  end
                end

              else
                local real_err = ""
                if token_info.error then
                  if token_info.error_description then
                    real_err = lower(tostring(token_info.error)) .. ": " ..
                               lower(tostring(token_info.error_description))
                  else
                    real_err = lower(tostring(token_info.error))
                  end

                elseif token_info.error_description then
                  real_err = lower(tostring(token_info.error_description))
                end

                if real_err == "" then
                  ins(logs.inactive)
                  return unauthorized(realm, "invalid_token", errs.inactive, logs.inactive)

                else
                  ins(logs.inactive, " (", real_err, ")")
                  return unauthorized(realm, "invalid_token", errs.inactive, logs.inactive, " (", real_err, ")")
                end
              end

            else
              ins(logs.introspection_endpoint)
              return unexpected(realm, "unexpected", errs.introspection_endpoint, logs.introspection_endpoint)
            end

          else
            log(logs.introspection_disabled)
            ins(logs.introspection_disabled)
          end

        else
          ins(logs.format)
          return unauthorized(realm, "invalid_token", errs.invalid, logs.format)
        end

        if type(payload) ~= "table" then
          ins(logs.payload)
          return unauthorized(realm, "invalid_token", errs.invalid, logs.payload)
        end

      else
        local optional = args.get_conf_arg(config.optional)
        if not optional then
          ins(logs.missing)
          return unauthorized(realm, "invalid_token", errs.invalid, logs.missing)

        else
          log(logs.optional)
          ins(logs.optional)
        end
      end
    else
      local optional = args.get_conf_arg(config.optional)
      if not optional then
        ins(logs.no_header)
        return unexpected(realm, "unexpected", errs.no_header, logs.no_header)

      else
        log(logs.optional)
        ins(logs.optional)
      end
    end

    if payload then
      local expiry

      if enable_introspection and not trust_introspection then
        local verify_expiry = args.get_conf_arg(config.verify_expiry)
        if verify_expiry then
          log(logs.expiring)
          ins(logs.expiring)

          local leeway = args.get_conf_arg(config.leeway, 0)

          expiry = tonumber(payload.exp)
          if expiry then
            if time() > (expiry + leeway) then
              ins(logs.expired)
              return unauthorized(realm, "invalid_token", errs.expired, logs.expired)
            end

          else
            ins(logs.expiry)
            return unauthorized(realm, "invalid_token", errs.expiry, logs.expiry)
          end
        end

        local verify_scopes = args.get_conf_arg(config.verify_scopes)
        if verify_scopes then
          log(logs.scopes)
          ins(logs.scopes)

          local scopes_required = args.get_conf_arg(config.scopes_required)
          if scopes_required then
            local scopes_claim = args.get_conf_arg(config.scopes_claim)
            if not scopes_claim then
              ins(logs.scopes_claim)
              return unexpected(realm, "unexpected", errs.scopes_claim, logs.scopes_claim)
            end

            local scopes = find_claim(payload, scopes_claim)
            if not scopes then
              ins(logs.no_scopes)
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

              ins(real_err)
              return forbidden(realm, "invalid_token", errs.invalid, real_err)
            end
          end
        end
      end

      if not consumer then
        local consumer_claim = args.get_conf_arg(config.consumer_claim)
        if consumer_claim then
          local consumer_by = args.get_conf_arg(config.consumer_by)
          if not consumer_by then
            ins(logs.consumer_by)
            return unexpected(realm, "unexpected", errs.consumer_by, logs.consumer_by)
          end

          local token_consumer = find_claim(payload, consumer_claim)
          if not token_consumer then
            ins(logs.consumer_claim)
            return forbidden(realm, "invalid_token", errs.invalid, logs.consumer_claim)
          end

          consumer, err = load_consumer(token_consumer, consumer_by)
          if not consumer then
            log(logs.consumer, token_consumer)
            ins(logs.consumer, token_consumer)
            return forbidden(realm, "invalid_token", errs.invalid, err)
          end
        end
      end

      local upstream_header = args.get_conf_arg(config.upstream_header)
      if upstream_header then
        log(logs.signing)
        ins(logs.signing)

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
          ins(err)
          return unexpected(realm, "unexpected", errs.keys_load, err)
        end

        local signing_algorithm = args.get_conf_arg(config.signing_algorithm)
        local jwk = private_keys[signing_algorithm]
        if not jwk then
          ins(logs.key_not_found)
          return unexpected(realm, "unexpected", errs.key_not_found, logs.key_not_found)
        end

        local signed_token
        signed_token, err = jws.encode({
          payload = payload,
          jwk     = jwk,
        })

        if not signed_token then
          ins(err)
          return unexpected(realm, "invalid_token", errs.signing, err)
        end

        log(logs.upstream_header)
        ins(logs.upstream_header)

        args.set_header(upstream_header, signed_token)
      end
    end
  end

  if consumer then
    log("setting consumer context and headers")
    ins("setting consumer context and headers")

    local id        = args.get_value(consumer.id)
    local username  = args.get_value(consumer.username)
    local custom_id = args.get_value(consumer.custom_id)

    local ctx = ngx.ctx
    ctx.authenticated_consumer = consumer
    ctx.authenticated_credential = {
      consumer_id = id,
    }

    local head = constants.HEADERS

    args.set_header(head.ANONYMOUS, nil)

    if id then
      args.set_header(head.CONSUMER_ID, id)
    else
      args.set_header(head.CONSUMER_ID, nil)
    end

    if custom_id then
      args.set_header(head.CONSUMER_CUSTOM_ID, custom_id)
    else
      args.set_header(head.CONSUMER_CUSTOM_ID, nil)
    end

    if username then
      args.set_header(head.CONSUMER_USERNAME, username)
    else
      args.set_header(head.CONSUMER_USERNAME, nil)
    end
  end

  ins("request finished")
end


JwtSignerHandler.PRIORITY = 999
JwtSignerHandler.VERSION  = "0.1.1"


return JwtSignerHandler
