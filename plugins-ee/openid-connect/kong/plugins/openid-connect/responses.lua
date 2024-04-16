-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local uri       = require "kong.openid-connect.uri"
local log       = require "kong.plugins.openid-connect.log"
local redirect  = require "kong.plugins.openid-connect.redirect"
local consumers = require "kong.plugins.openid-connect.consumers"
local error_codes = require "kong.enterprise_edition.oauth.error_codes"
local table_merge = require("kong.tools.utils").table_merge


local ForbiddenError = error_codes.ForbiddenError
local UnauthorizedError = error_codes.UnauthorizedError


local DPOP_ALGS = require("kong.openid-connect.jwa").get_dpop_algs()


local kong = kong


local function unauthorized(error_o, ctx, client, anonymous, session)
  local err = error_o.log
  local msg = error_o.message
  if err then
    log.notice(err)
  end

  if session and client.unauthorized_destroy_session then
    session:destroy()
  end

  if anonymous then
    return consumers.anonymous(ctx, anonymous, client)
  end

  if client.unauthorized_redirect_uri then
    return redirect(client.unauthorized_redirect_uri)
  end

  if client.display_errors and err then
    msg = msg .. " (" .. err .. ")"
  end

  local status_code = error_o.status_code
  return kong.response.exit(status_code, { message = msg },
    { ["WWW-Authenticate"] = error_o:build_www_auth_header() })
end


local function forbidden(error_o, ctx, client, anonymous, session)
  local err = error_o.log
  local msg = error_o.message
  if err then
    log.notice(err)
  end

  if session and client.forbidden_destroy_session then
    session:destroy()
  end

  if anonymous then
    return consumers.anonymous(ctx, anonymous, client)
  end

  if client.forbidden_redirect_uri then
    return redirect(client.forbidden_redirect_uri)
  end

  if client.display_errors and err then
    msg = msg .. " (" .. err .. ")"
  end

  local status_code = error_o.status_code
  return kong.response.exit(status_code, { message = msg },
    { ["WWW-Authenticate"] = error_o:build_www_auth_header() })
end


local function success(response)
  if not response then
    return kong.response.exit(204)
  end

  return kong.response.exit(200, response)
end


local function get_fields(issuer, fields, dpop_needed)
  -- generating default fields for the WWW-Authenticate header
  local parts = uri.parse(issuer)
  local host = parts.host
  local default_fields = { realm = host or "kong", }
  if dpop_needed then
    default_fields.algs = DPOP_ALGS
  end
  if fields then
    return table_merge(fields, default_fields)
  end
  return default_fields
end


local function new(args, ctx, issuer, client, anonymous, session)
  local forbidden_msg = args.get_conf_arg("forbidden_error_message", "Forbidden")
  local unauth_msg = args.get_conf_arg("unauthorized_error_message", "Unauthorized")
  local expose_error_code = args.get_conf_arg("expose_error_code", true)
  local dpop_needed = args.get_conf_arg("proof_of_possession_dpop") == "strict"
  local default_token_type = dpop_needed and "DPoP" or "Bearer"

  return {
    forbidden = function(log_message, error_code, error_description, token_type, fields, headers)
      local error_o = ForbiddenError:new{
        token_type = token_type or default_token_type,
        fields = get_fields(issuer, fields, dpop_needed),
        headers = headers,
        message = forbidden_msg,
        error_code = error_code,
        error_description = error_description,
        expose_error_code = expose_error_code,
        log_msg = log_message,
      }
      return unauthorized(error_o, ctx, client, anonymous, session)
    end,
    unauthorized = function(log_message, error_code, error_description, token_type, fields, headers)
      local error_o = UnauthorizedError:new {
        token_type = token_type or default_token_type,
        fields = get_fields(issuer, fields, dpop_needed),
        headers = headers,
        message = unauth_msg,
        error_code = error_code,
        error_description = error_description,
        expose_error_code = expose_error_code,
        log_msg = log_message,
      }
      return unauthorized(error_o, ctx, client, anonymous, session)
    end,
    success = success,
    redirect = redirect,
  }
end


return {
  new          = new,
  unauthorized = unauthorized,
  forbidden    = forbidden,
  success      = success,
  redirect     = redirect,
}
