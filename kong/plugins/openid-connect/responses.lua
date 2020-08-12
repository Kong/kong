local uri       = require "kong.openid-connect.uri"
local log       = require "kong.plugins.openid-connect.log"
local consumers = require "kong.plugins.openid-connect.consumers"


local kong      = kong
local select    = select
local concat    = table.concat
local redirect  = ngx.redirect


local function unauthorized(err, msg, ctx, issuer, client, anonymous, session)
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

  return kong.response.exit(401, { message = msg }, {
    ["WWW-Authenticate"] = 'Bearer realm="' .. (parts.host or "kong") .. '"'
  })
end


local function forbidden(err, msg, ctx, issuer, client, anonymous, session)
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

  return kong.response.exit(403, { message = msg }, {
    ["WWW-Authenticate"] = 'Bearer realm="' .. (parts.host or "kong") .. '"'
  })
end


local function success(response)
  if not response then
    return kong.response.exit(204)
  end

  return kong.response.exit(200, response)
end


local function new(args, ctx, issuer, client, anonymous, session)
  return {
    forbidden = function(...)
      local msg = args.get_conf_arg("forbidden_error_message", "Forbidden")
      local err
      local count = select("#", ...)
      if count == 1 then
        err = select(1, ...)
      elseif count > 1 then
        err = concat({ ... })
      end

      return forbidden(err, msg, ctx, issuer, client, anonymous, session)
    end,
    unauthorized = function(...)
      local msg = args.get_conf_arg("unauthorized_error_message", "Unauthorized")
      local err
      local count = select("#", ...)
      if count == 1 then
        err = select(1, ...)
      elseif count > 1 then
        err = concat({ ... })
      end

      return unauthorized(err, msg, ctx, issuer, client, anonymous, session)
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
