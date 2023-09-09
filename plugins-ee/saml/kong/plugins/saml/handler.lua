-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]


local meta = require "kong.meta"


local SAMLHandler = {
  PRIORITY = 900,
  VERSION = meta.core_version,
}


local utils      = require "kong.tools.utils"
local log        = require "kong.plugins.saml.log"
local sessions   = require "kong.plugins.saml.sessions"
local consumers  = require "kong.plugins.saml.consumers"
local saml       = require "kong.plugins.saml.saml"
local helpers    = require "kong.plugins.saml.utils.helpers"
local crypt      = require "kong.plugins.saml.utils.crypt"
local cjson      = require "cjson"
local base64     = require "ngx.base64"
local pl_stringx = require "pl.stringx"


local kong = kong
local render_request_form = helpers.render_request_form


-- create an authentication request to be sent to the IdP and respond
-- with an HTML form that automatically submits itself to the IdP as a
-- POST request.
local function handle_login_request(config)
  log("handling authn request")
  local request_id = "_" .. utils.uuid()
  local assertion, err = saml.build_login_request(request_id, config)
  if err then
    return false, err
  end

  local relay_state = {
    verb = ngx.req.get_method(),
    uri = ngx.var.request_uri,
    request_id = request_id,
  }

  if relay_state.verb == "POST" then
    if  kong.request.get_header("content-type") ~= "application/x-www-form-urlencoded" then
      return kong.response.exit(415, { message = "Unsupported Media Type" })
    end

    ngx.req.read_body()
    log("saving POSTed form data in relay state")
    relay_state.form_data = ngx.req.get_post_args()
  end

  -- set request binding to POST only, but keeping this option in case other IdPs support GET
  render_request_form("POST", config.idp_sso_url, {
      RelayState = crypt.encrypt(cjson.encode(relay_state), config.session_secret),
      SAMLRequest = ngx.encode_base64(assertion),
  })
end


local function decode_login_response_body(config)
  log("decode login response body")
  kong.request.get_raw_body()
  local posted = kong.request.get_body()

  if not posted then
    return nil, nil, "No response received or response too large to be buffered in memory"
  end

  if not posted.SAMLResponse then
    return nil, nil, "No SAMLResponse field found in response body"
  end

  local xml_text = ngx.decode_base64(posted.SAMLResponse) or base64.decode_base64url(posted.SAMLResponse)
  if not xml_text then
    return nil, nil, "SAMLResponse field could not be decoded"
  end

  local relay_state = posted.RelayState
  if not relay_state then
    return nil, nil, "RelayState missing"
  end

  return xml_text, cjson.decode(crypt.decrypt(relay_state, config.session_secret))
end


function SAMLHandler:access(config)
  log("in access phase")
  local ctx = ngx.ctx

  local anonymous = config.anonymous
  if anonymous and ctx.authenticated_credential then
    -- we're already authenticated, and we're configured for using anonymous,
    -- hence we're in a logical OR between auth methods and we're already done.
    log("skipping because user is already authenticated")
    return
  end

  -- initialize functions
  local session_open = sessions.new(config, config.session_secret)

  -- try to open session
  local session_secure = config.session_cookie_secure
  if session_secure == nil then
    session_secure = kong.request.get_forwarded_scheme() == "https"
  end

  -- http_only can be configured via both parameters:
  -- session_cookie_http_only and session_cookie_httponly
  -- it defaults to true if not configured
  local http_only
  if config.session_cookie_http_only == nil then
    http_only = config.session_cookie_httponly == nil or config.session_cookie_httponly
  else
    http_only = config.session_cookie_http_only
  end

  local session, session_error, session_present = session_open({
    cookie_name               = config.session_cookie_name or "session",
    remember_cookie_name      = config.session_remember_cookie_name or "remember",
    remember                  = config.session_remember or false,
    remember_rolling_timeout  = config.session_remember_rolling_timeout or 604800,
    remember_absolute_timeout = config.session_remember_absolute_timeout or 2592000,
    idling_timeout            = config.session_idling_timeout or config.session_cookie_idletime or 900,
    rolling_timeout           = config.session_rolling_timeout or config.session_cookie_lifetime or 3600,
    absolute_timeout          = config.session_absolute_timeout or 86400,
    cookie_path               = config.session_cookie_path or "/",
    cookie_domain             = config.session_cookie_domain,
    cookie_same_site          = config.session_cookie_same_site or config.session_cookie_samesite or "Lax",
    cookie_http_only          = http_only,
    request_headers           = config.session_request_headers,
    response_headers          = config.session_response_headers,
    cookie_secure             = session_secure,
  })

  if session_present then
    log("session present, hiding session cookie from upstream")
    session:clear_request_cookie()

  else
    if session_error then
      log.err("session was not found (", session_error, ")")
    else
      log.err("session was not found")
    end
  end

  local uri = kong.request.get_path()
  local method = kong.request.get_method()
  if pl_stringx.endswith(uri, config.assertion_consumer_path) and method == "POST" then
    -- We're processing a callback initiated by the IdP
    local xml_text, relay_state, err = decode_login_response_body(config)
    if not xml_text then
      log.notice("cannot decode body: " .. err)
      return kong.response.exit(400, { message = "Invalid request" })
    end

    local assertion
    assertion, err = saml.parse_and_validate_login_response(xml_text, nil, relay_state.request_id, config)
    if not assertion then
      log.notice("user is unauthorized with error: " .. err)
      return kong.response.exit(401, { message = "Unauthorized" })
    end

    -- save session
    session:set_data({
      session_idx = assertion.session_idx,
      -- create JWT like token which can be expanded in the future to support SAML v3 tokens
      token = {
        header = {
          type = "JWT",
        },
        claims = {
          iss = assertion.issuer,
          sub = assertion.username,
        },
      },
    })
    local ok, err = session:save()
    if not ok then
      local message = "Cannot save session data"
      log.err(message .. ": " .. err or "(no error information provided)")
      return kong.response.exit(500, { message = message })
    end

    log("forwarding client to original " .. relay_state.verb .. " " .. relay_state.uri)

    if relay_state.verb == "POST" then
      log("redirecting as POST using form")
      render_request_form("POST", relay_state.uri, relay_state.form_data)
    else
      log("redirecting as GET")
      ngx.header["Location"] = relay_state.uri
      return kong.response.exit(302)
    end

  else
    -- We're handling a normal request, not an IdP callback invocation
    if session_present then
      -- Session was authenticated, look up consumer

      -- TODO: this looks like a bug, it always prefers anonymous, when configured!
      local consumer_id = anonymous or session:get_data().token.claims.sub
      -- fixme: Why don't we put the consumer into the session instead
      -- of performing the lookup for every request?
      local consumer, err = consumers.find(consumer_id)
      if not consumer then
        if err then
          log.err("consumer " .. consumer_id .. " not found: " .. err)
        else
          log.err("consumer " .. consumer_id .. " not found")
        end

        -- TODO: should we start a flow in this case uf the Accept header has text/html?
        return kong.response.exit(401, { message = "Unauthorized" })

      end

      -- set customer related context and response headers and pass
      -- the request to the upstream
      consumers.set(ctx, consumer)

      local ok, err = session:refresh()
      if not ok then
        if err then
          log.warn("session refresh failed (", err, ")")
        else
          log.warn("session refresh failed")
        end
      end

      session:set_headers()

    else
      -- Request is not yet authenticated, respond with the login form
      -- if we're coming from a browser
      local accept_header = kong.request.get_header("Accept")
      if accept_header and accept_header:match("text/html") then
        handle_login_request(config)
      else
        -- Request is not coming from a browser, respond with 401 to
        -- indicate that browser based login is needed
        return kong.response.exit(401, { message = "Unauthorized" })
      end
    end
  end
end

return SAMLHandler
