-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local log      = require "kong.plugins.openid-connect.log"


local kong     = kong
local tonumber = tonumber
local timer_at = ngx.timer.at
local ipairs   = ipairs


local PRIVATE_KEY_JWKS = {}


local function prepare_private_key_jwks(premature)
  if premature then
    return
  end

  local keys, err = kong.db.oic_jwks:get()
  if not keys then
    if err then
      log.err(err)
    end

  else
    local jwks = {}
    for _, jwk in ipairs(keys.jwks.keys) do
      if jwk.alg ~= "HS256" and jwk.alg ~= "HS384" and jwk.alg ~= "HS512" then
        jwks[jwk.alg] = jwk
      end
    end

    PRIVATE_KEY_JWKS = jwks
  end
end


local function init_worker()
  kong.db.oic_jwks.init_worker()
  local ok, err = timer_at(0, prepare_private_key_jwks)
  if not ok then
    log.err(err)
  end
end


local function find_client_by_arg(arg, clients)
  if not arg then
    return nil
  end

  local client_index = tonumber(arg, 10)
  if client_index then
    if clients[client_index] then
      local client_id = clients[client_index]
      if client_id then
        return client_id, client_index
      end
    end

    return
  end

  for i, c in ipairs(clients) do
    if arg == c then
      return clients[i], i
    end
  end
end


local function find_client(args)
  -- load client configuration
  local clients        = args.get_conf_arg("client_id",      {})
  local secrets        = args.get_conf_arg("client_secret",  {})
  local auths          = args.get_conf_arg("client_auth",    {})
  local algs           = args.get_conf_arg("client_alg",     {})
  local jwks           = args.get_conf_arg("client_jwk",     {})
  local redirects      = args.get_conf_arg("redirect_uri",   {})
  local display_errors = args.get_conf_arg("display_errors", false)

  local login_redirect_uris        = args.get_conf_arg("login_redirect_uri",        {})
  local logout_redirect_uris       = args.get_conf_arg("logout_redirect_uri",       {})
  local forbidden_redirect_uris    = args.get_conf_arg("forbidden_redirect_uri",    {})
  local unauthorized_redirect_uris = args.get_conf_arg("unauthorized_redirect_uri", {})
  local unexpected_redirect_uris   = args.get_conf_arg("unexpected_redirect_uri",   {})

  clients.n = #clients

  local client_id
  local client_index

  if clients.n > 1 then
    local client_arg_name = args.get_conf_arg("client_arg", "client_id")
    client_id, client_index = find_client_by_arg(args.get_header(client_arg_name, "X"), clients)
    if not client_id then
      client_id, client_index = find_client_by_arg(args.get_uri_arg(client_arg_name), clients)
      if not client_id then
        client_id, client_index = find_client_by_arg(args.get_body_arg(client_arg_name), clients)
      end
    end
  end

  local client = {
    clients                      = clients,
    secrets                      = secrets,
    auths                        = auths,
    algs                         = algs,
    jwks                         = jwks,
    redirects                    = redirects,
    login_redirect_uris          = login_redirect_uris,
    logout_redirect_uris         = logout_redirect_uris,
    forbidden_redirect_uris      = forbidden_redirect_uris,
    forbidden_destroy_session    = args.get_conf_arg("forbidden_destroy_session", true),
    unauthorized_destroy_session = args.get_conf_arg("unauthorized_destroy_session", true),
    unauthorized_redirect_uris   = unauthorized_redirect_uris,
    unexpected_redirect_uris     = unexpected_redirect_uris,
  }

  if client_id then
    client.id                        = client_id
    client.index                     = client_index
    client.secret                    = secrets[client_index]                    or secrets[1]
    client.auth                      = auths[client_index]                      or auths[1]
    client.jwk                       = jwks[client_index]                       or jwks[1]
    client.alg                       = algs[client_index]                       or algs[1]
    client.redirect_uri              = redirects[client_index]                  or redirects[1]
                                                                                or args.get_redirect_uri()
    client.login_redirect_uri        = login_redirect_uris[client_index]        or login_redirect_uris[1]
    client.logout_redirect_uri       = logout_redirect_uris[client_index]       or logout_redirect_uris[1]
    client.forbidden_redirect_uri    = forbidden_redirect_uris[client_index]    or forbidden_redirect_uris[1]
    client.unauthorized_redirect_uri = unauthorized_redirect_uris[client_index] or unauthorized_redirect_uris[1]
    client.unexpected_redirect_uri   = unexpected_redirect_uris[client_index]   or unexpected_redirect_uris[1]

  else
    client.id                        = clients[1]
    client.index                     = 1
    client.secret                    = secrets[1]
    client.auth                      = auths[1]
    client.alg                       = algs[1]
    client.jwk                       = jwks[1]
    client.redirect_uri              = redirects[1] or args.get_redirect_uri()
    client.login_redirect_uri        = login_redirect_uris[1]
    client.logout_redirect_uri       = logout_redirect_uris[1]
    client.forbidden_redirect_uri    = forbidden_redirect_uris[1]
    client.unauthorized_redirect_uri = unauthorized_redirect_uris[1]
    client.unexpected_redirect_uri   = unexpected_redirect_uris[1]
  end

  if not client.jwk then
    if kong.configuration.database == "off" then
      prepare_private_key_jwks()
    end
    client.jwk = PRIVATE_KEY_JWKS[client.alg] or PRIVATE_KEY_JWKS.RS256
  end

  client.display_errors = display_errors

  return client
end


local function reset_client(idx, client, oic, options)
  if not idx or idx == client.index or client.clients.n < 2 then
    return
  end

  local new_id, new_idx = find_client_by_arg(idx, client.clients)
  if not new_id then
    return
  end

  client.index                     = new_idx
  client.id                        = new_id
  client.secret                    = client.secrets[new_idx]                    or client.secret
  client.auth                      = client.auths[new_idx]                      or client.auth
  client.jwk                       = client.jwk[new_idx]                        or client.jwk
  client.alg                       = client.algs[new_idx]                       or client.alg
  client.redirect_uri              = client.redirects[new_idx]                  or client.redirect_uri
  client.login_redirect_uri        = client.login_redirect_uris[new_idx]        or client.login_redirect_uri
  client.logout_redirect_uri       = client.logout_redirect_uris[new_idx]       or client.logout_redirect_uri
  client.forbidden_redirect_uri    = client.forbidden_redirect_uris[new_idx]    or client.forbidden_redirect_uri
  client.unauthorized_redirect_uri = client.unauthorized_redirect_uris[new_idx] or client.unauthorized_redirect_uri
  client.unexpected_redirect_uri   = client.unexpected_redirect_uris[new_idx]   or client.unexpected_redirect_uri

  if not client.jwk then
    if kong.configuration.database == "off" then
      prepare_private_key_jwks()
    end
    client.jwk = PRIVATE_KEY_JWKS[client.alg] or PRIVATE_KEY_JWKS.RS256
  end

  options.client_id     = client.id
  options.client_secret = client.secret
  options.client_auth   = client.auth
  options.client_alg    = client.alg
  options.redirect_uri  = client.redirect_uri

  oic.options:reset(options)
end


return {
  init_worker = init_worker,
  find        = find_client,
  reset       = reset_client,
}
