-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local stringx = require "pl.stringx"
local jwt = require "resty.jwt"

local sessions = require "kong.plugins.openid-connect.sessions"
local cache = require "kong.plugins.openid-connect.cache"

local sub = string.sub
local find = string.find
local split = stringx.split
local lower = string.lower
local kong = kong
local ipairs = ipairs
local decode_base64 = ngx.decode_base64
local type = type

local function decode_basic_auth(basic_auth)
  if not basic_auth then
    return
  end

  local s = find(basic_auth, ":", 2, true)
  if s then
    local username = sub(basic_auth, 1, s - 1)
    local password = sub(basic_auth, s + 1)
    return username, password
  end
end

-- client_credentials_get parses the request header and returns the credentials
-- passed or returns nil
---@return string username
---@return string password
local function client_credentials_get()
  local auth_header = kong.request.get_header("authorization")
  if not auth_header then
    return
  end
  local prefix
  prefix = lower(sub(auth_header, 1, 5))
  if prefix ~= "basic" then
    return
  end
  local creds = sub(auth_header, 7)
  return decode_basic_auth(decode_base64(creds))
end

-- bearer_get parses the request header and returns jwt table
-- passed or returns nil. Note: a non valid jwt would be `jwt_obj.valid = false`
---@return table jwt object from "resty.jwt"
local function bearer_get()
  local auth_header = kong.request.get_header("authorization")
  if not auth_header then
    return nil
  end
  local prefix
  prefix = lower(sub(auth_header, 1, 6))
  if prefix ~= "bearer" then
    return nil
  end
  local token = sub(auth_header, 8)
  local jwt_obj = jwt:load_jwt(token)
  return jwt_obj
end

-- get_cookie parses the `Cookie` header of the request and extract only the
-- cookie passed in parameter, if no value is found it returns nil
---@param cookie string name to look for
---@return string cookie value
local function get_cookie(cookie_name)
  local cookie_header = kong.request.get_header("cookie")
  if not cookie_header then
    return
  end

  local cookie_slice = split(cookie_header, ";")
  for _, cookie in ipairs(cookie_slice) do
    -- find first `=` then get second part
    local sep_idx = find(cookie, "=", 1, true)
    if sep_idx then
      return sub(cookie, sep_idx + 1)
    end
  end
end

-- Opens a session from openid-connect
---@param args table imported from "kong.plugins.openid-connect.arguments"
---@param issuer table loaded using "kong.plugins.openid-connect.cache" and cache.issuers.load
---@return table session
---@return table session_error
---@return boolean session_present
local function open_session(args, issuer)
  local secret = args.get_conf_arg("session_secret")
  if not secret then
    secret = issuer.secret
  end
  local session_open = sessions.new(args, secret)

  local session_secure = args.get_conf_arg("session_cookie_secure")
  if session_secure == nil then
    session_secure = kong.request.get_forwarded_scheme() == "https"
  end

  -- http_only can be configured via both parameters:
  -- session_cookie_http_only and session_cookie_httponly
  -- it defaults to true if not configured
  local http_only = args.get_conf_arg("session_cookie_http_only")
  if http_only == nil then
    http_only = args.get_conf_arg("session_cookie_httponly", true)
  end

  return session_open({
    cookie_name = args.get_conf_arg("session_cookie_name", "session"),
    remember_cookie_name = args.get_conf_arg("session_remember_cookie_name", "remember"),
    remember = args.get_conf_arg("session_remember", false),
    remember_rolling_timeout = args.get_conf_arg("session_remember_rolling_timeout", 604800),
    remember_absolute_timeout = args.get_conf_arg("session_remember_absolute_timeout", 2592000),
    idling_timeout = args.get_conf_arg("session_idling_timeout") or args.get_conf_arg("session_cookie_idletime", 900),
    rolling_timeout = args.get_conf_arg("session_rolling_timeout") or args.get_conf_arg("session_cookie_lifetime", 3600),
    absolute_timeout = args.get_conf_arg("session_absolute_timeout", 86400),
    cookie_path = args.get_conf_arg("session_cookie_path", "/"),
    cookie_domain = args.get_conf_arg("session_cookie_domain"),
    cookie_same_site = args.get_conf_arg("session_cookie_same_site") or
      args.get_conf_arg("session_cookie_samesite", "Lax"),
    cookie_http_only = http_only,
    request_headers = args.get_conf_arg("session_request_headers"),
    response_headers = args.get_conf_arg("session_response_headers"),
    cookie_secure = session_secure
  })
end

--- Get the issuer from the openid config
---@param args table imported from "kong.plugins.openid-connect.arguments"
---@return table issuer
local function get_issuer(args)
  local issuer_uri = args.get_conf_arg("issuer")

  local discovery_options = args.get_http_opts({
    headers = args.get_conf_args("discovery_headers_names", "discovery_headers_values"),
    rediscovery_lifetime = args.get_conf_arg("rediscovery_lifetime", 30),
    extra_jwks_uris = args.get_conf_arg("extra_jwks_uris"),
    using_pseudo_issuer = args.get_conf_arg("using_pseudo_issuer", false)
  })

  local issuer, err = cache.issuers.load(issuer_uri, discovery_options)
  if type(issuer) ~= "table" then
    return error(err or "discovery information could not be loaded")
  end
  return issuer
end

return {
  bearer_get = bearer_get,
  open_session = open_session,
  get_issuer = get_issuer,
  get_cookie = get_cookie,
  client_credentials_get = client_credentials_get
}
