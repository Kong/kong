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

local ForbiddenError = error_codes.ForbiddenError
local UnauthorizedError = error_codes.UnauthorizedError


local kong = kong

local function unauthorized(error_o, ctx, issuer, client, anonymous, session)
  local err = error_o.log
  local msg = error_o.message
  if err then
    log.notice(err)
  end

  if session and session.present then
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

  local parts = uri.parse(issuer)

  local status_code = error_o.status_code
  local header = error_o:build_auth_header(parts.host)
  return kong.response.exit(status_code, { message = msg }, header)
end


local function forbidden(error_o, ctx, issuer, client, anonymous, session)
  local err = error_o.log
  local msg = error_o.message
  if err then
    log.notice(err)
  end

  if session and session.present and client.forbidden_destroy_session then
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

  local parts = uri.parse(issuer)

  local status_code = error_o.status_code
  local header = error_o:build_auth_header(parts.host)
  return kong.response.exit(status_code, { message = msg }, header)
end


local function success(response)
  if not response then
    return kong.response.exit(204)
  end

  return kong.response.exit(200, response)
end


local function new(args, ctx, issuer, client, anonymous, session)
  return {
    forbidden = function(log_message, error_description, expose_error_code)
      local msg = args.get_conf_arg("forbidden_error_message", "Forbidden")
      local error_o = ForbiddenError:new{
        message = msg,
        error_description = error_description,
        expose_error_code = expose_error_code,
        log_msg = log_message,
      }
      return unauthorized(error_o, ctx, issuer, client, anonymous, session)
    end,
    unauthorized = function(log_message, error_description, expose_error_code)
      local msg = args.get_conf_arg("unauthorized_error_message", "Unauthorized")
      local error_o = UnauthorizedError:new {
        message = msg,
        error_description = error_description,
        expose_error_code = expose_error_code,
        log_msg = log_message,
      }
      return unauthorized(error_o, ctx, issuer, client, anonymous, session)
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
