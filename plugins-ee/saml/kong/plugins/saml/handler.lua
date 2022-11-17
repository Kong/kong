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

local ngx                 = ngx
local kong                = kong

local log                 = require "kong.plugins.saml.log"
local sessions            = require "kong.plugins.saml.sessions"
local consumers           = require "kong.plugins.saml.consumers"
local saml                = require "kong.plugins.saml.saml"
local helpers             = require "kong.plugins.saml.utils.helpers"
local crypt               = require "kong.plugins.saml.utils.crypt"
local cjson               = require "cjson"
local base64              = require "ngx.base64"
local pl_stringx          = require "pl.stringx"

local render_request_form = helpers.render_request_form
local lower               = string.lower


-- create an authentication request to be sent to the IdP and respond
-- with an HTML form that automatically submits itself to the IdP as a
-- POST request.
local function handle_login_request(conf)
  log("handling authn request")
  local assertion, err = saml.build_login_request(conf)
  if err then
    return false, err
  end

  local relay_state = {
    verb = ngx.req.get_method(),
    uri = ngx.var.request_uri
  }

  if relay_state.verb == "POST" then
    if  kong.request.get_header("content-type") ~= "application/x-www-form-urlencoded" then
      return kong.response.exit(415, { message = "Unsupported Media Type" })
    end

    ngx.req.read_body()
    log("saving POSTed form data in relay state")
    relay_state.data = crypt.encrypt(cjson.encode(ngx.req.get_post_args()), conf["session_secret"])
  end

  -- set request binding to POST only, but keeping this option in case other IdPs support GET
  render_request_form("POST", conf["idp_sso_url"], {
      RelayState = ngx.encode_base64(cjson.encode(relay_state)),
      SAMLRequest = ngx.encode_base64(assertion),
  })
end


local function decode_relay_state(relay_state)
  if relay_state and relay_state ~= "" then
    return cjson.decode(ngx.decode_base64(relay_state))
  else
    return { verb = "", uri = "" }
  end
end


local function decode_login_response_body(conf)
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

  log("Relay state: ", posted.RelayState)

  local relay_state = decode_relay_state(posted.RelayState)

  return xml_text, relay_state
end


function SAMLHandler:access(conf)
  log("in access phase")
  local ctx = ngx.ctx

  local anonymous = conf["anonymous"]
  if anonymous and ctx.authenticated_credential then
    -- we're already authenticated, and we're configured for using anonymous,
    -- hence we're in a logical OR between auth methods and we're already done.
    log("skipping because user is already authenticated")
    return
  end

  -- initialize functions
  local session_open = sessions.new(conf, conf["session_secret"])
  -- try to open session
  local session_secure = conf["session_cookie_secure"]
  if session_secure == nil then
    local scheme
    if kong.ip.is_trusted(ngx.var.realip_remote_addr or ngx.var.remote_addr) then
      scheme = ngx.req.get_headers()["X-Forwarded-Proto"]
    else
      scheme = ngx.var.scheme
    end

    if type(scheme) == "table" then
      scheme = scheme[1]
    end

    session_secure = lower(scheme) == "https"
  end

  local session, session_present, session_error = session_open {
    name = conf["session_cookie_name"],
    cookie = {
      lifetime = conf["session_cookie_lifetime"],
      idletime = conf["session_cookie_idletime"],
      renew    = conf["session_cookie_renew"],
      path     = conf["session_cookie_path"],
      domain   = conf["session_cookie_domain"],
      samesite = conf["session_cookie_samesite"],
      httponly = conf["session_cookie_httponly"],
      maxsize  = conf["session_cookie_maxsize"],
      secure   = session_secure,
    },
  }

  if session_present then
    log("session present, hiding session cookie from upstream")
    session:hide()
  else
    if session_error then
      log.err("session was not found (", session_error, ")")
    else
      log.err("session was not found")
    end
  end

  local uri = kong.request.get_path()
  local method = kong.request.get_method()
  if pl_stringx.endswith(uri, conf["assertion_consumer_path"]) and method == "POST" then
    -- We're processing a callback initiated by the IdP
    local xml_text, relay_state, err = decode_login_response_body(conf)
    if not xml_text then
      log.notice("cannot decode body: " .. err)
      return kong.response.exit(400, { message = "Invalid request" })
    end

    local assertion, err = saml.parse_and_validate_login_response(xml_text, conf)
    if not assertion then
      log.notice("user is unauthorized with error: " .. err)
      return kong.response.exit(401, { message = "Unauthorized" })
    end

    -- save session
    session.data = {
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
    }
    session:save()

    log("forwarding client to original " .. relay_state.verb .. " " .. relay_state.uri)

    if relay_state.verb == "POST" then
      log("redirecting as POST using form")
      render_request_form("POST", relay_state.uri, cjson.decode(crypt.decrypt(relay_state.data, conf["session_secret"])))
    else
      log("redirecting as GET")
      ngx.header["Location"] = relay_state.uri
      return kong.response.exit(302)
    end
  else
    -- We're handling a normal request, not an IdP callback invocation
    if session_present then
      -- Session was authenticated, look up consumer
      local consumer_id = anonymous or session.data.token.claims.sub
      -- fixme: Why don't we put the consumer into the session instead
      -- of performing the lookup for every request?
      local consumer, err = consumers.find(consumer_id)
      if not consumer then
        if err then
          log.err("consumer " .. consumer_id .. " not found: " .. err)
        else
          log.err("consumer " .. consumer_id .. " not found")
        end
        return kong.response.exit(401, { message = "Unauthorized" })
      end
      -- set customer related context and response headers and pass
      -- the request to the upstream
      consumers.set(ctx, consumer)
    else
      -- Request is not yet authenticated, respond with the login form
      -- if we're coming from a browser
      local accept_header = kong.request.get_header("Accept")
      if accept_header and accept_header:match("text/html") then
        handle_login_request(conf)
      else
        -- Request is not coming from a browser, respond with 401 to
        -- indicate that browser based login is needed
        return kong.response.exit(401, { message = "Unauthorized" })
      end
    end
  end
end

return SAMLHandler
