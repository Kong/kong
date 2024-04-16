-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local utils = require("kong.tools.utils")
local resty_http = require("resty.http")
local cjson = require("cjson")
local jwks = require "kong.openid-connect.jwks"
local jwa = require("kong.openid-connect.jwa")
local uuid = require("resty.jit-uuid")
local base64url_encode = require("ngx.base64").encode_base64url
local json_encode = cjson.encode


local WELL_KNOWN_PATH = "/.well-known/openid-configuration"
local ENDPOINT_SUFFIX = "_endpoint"


local _M = {}


---- utility functions

local function dump_request(url, opts, is_rp)
  print("\n==", is_rp and "RP" or "IDP", " request==")
  print(opts.method, " ", url)
  for k, v in pairs(opts.headers) do
    print(k, ": ", v)
  end
  print()
  print(opts.body)
  print("===============")
end


local function dump_response(resp, is_rp)
  print("\n==", is_rp and "RP" or "IDP", " response==")
  print("HTTP ", resp.status)
  for k, v in pairs(resp.headers) do
    print(k, ": ", v)
  end
  print()
  print(resp.body)
  print("===============")
end


local function get_value_fallback(key, ...)
  for i = 1, select("#", ...) do
    local source = select(i, ...)
    if source[key] then
      return source[key]
    end
  end
end


function _M.update_cookies(self, res)
  local set_cookie_headers = res.headers["Set-Cookie"]
  if type(set_cookie_headers) ~= "table" then
    set_cookie_headers = { set_cookie_headers }
  end

  for _, cookie in ipairs(set_cookie_headers) do
    local k, v = cookie:match("^([^;=]*)=([^;=]*)")
    self.cookies[k] = v or ""
  end
end


local function cookies_to_header(cookies)
  local cookie = {}
  for k, v in pairs(cookies) do
    cookie[#cookie + 1] = k .. "=" .. v
  end
  return table.concat(cookie, "; ")
end


local function append_query(url, args)
  if url:find("?") then
    return url .. "&" .. args
  else
    return url .. "?" .. args
  end
end


---- end of utility functions

---- methods

-- to use a public client, set client_secret to false explicitly
function _M.new(opts)
  opts.http_client = opts.http_client or resty_http.new()
  opts.issuer = opts.issuer or "http://localhost:8080/realms/master"
  opts.client_uri = opts.client_uri or "http://localhost"
  opts.auth_callback_uri = opts.auth_callback_uri or "/callback/auth/"
  opts.user_login_simulator = opts.user_login_simulator or _M.keycloak_login
  opts.cookies = opts.cookies or {}

  -- default to using end-to-end binding unless explicitly set to false
  if opts.using_dpop and opts.auth_dpop == nil then
    opts.auth_dpop = true
  end

  return setmetatable(opts, _M)
end

function _M.__index(self, key)
  if _M[key] then
    return _M[key]
  end

  if key:sub(-#ENDPOINT_SUFFIX) == ENDPOINT_SUFFIX then
    local ret = self:get_endpoint(key)
    self[key] = ret
    return ret
  end

  local get_f = "get_" .. key
  if _M[get_f] then
    self[key] = _M[get_f](self)
    return self[key]
  end
end

function _M:get_idp_config()
  local issuer = self.issuer
  if not issuer then
    error("no discovery_url set")
  end

  if issuer:sub(-#WELL_KNOWN_PATH) ~= WELL_KNOWN_PATH then
    issuer = issuer .. WELL_KNOWN_PATH
  end

  local res, err = self:idp_request(issuer, {
    method = "GET",
    headers = {
      ["Accept"] = "application/json",
    },
  })

  if not res then
    error("failed to fetch openid-configuration: " .. err)
  end

  if res.status ~= 200 then
    error("failed to fetch openid-configuration: status " .. res.status)
  end

  return cjson.decode(res.body)
end


function _M:generate_dpop_proof(req, payload, alg)
  local jwk = assert(self.client_jwk, "no client_jwk set")
  local jwk_public = assert(self.client_jwk_public, "no client_jwk set")
  local htm = assert(req.method, "request method required to sign DPoP header")
  local htu = assert(req.url, "request uri required to sign DPoP header")
  htu = htu:match("^[^?#]*") -- remove query string and fragment
  payload = payload or {}

  if (not payload.ath) and payload.access_token then
    payload.ath = base64url_encode(jwa.S256(payload.access_token))
    payload.access_token = nil
  end

  local header = {
    typ = "dpop+jwt",
    alg = alg or jwk.alg,
    jwk = jwk_public,
  }

  for k, v in pairs(payload) do
    payload[k] = v
  end

  payload.iat = payload.iat or ngx.now()
  payload.jti = payload.jti or uuid.generate_v4()
  payload.htm = payload.htm or htm
  payload.htu = payload.htu or htu

  local str_to_sign = base64url_encode(json_encode(header)) .. "." .. base64url_encode(json_encode(payload))

  local jwt_token = assert(jwa.sign(header.alg, jwk, str_to_sign))

  return str_to_sign .. "." .. jwt_token
end


function _M:get_endpoint(name)
  local idp_config = assert(self.idp_config, "no idp_config set")
  local endpoint

  if self.using_mtls and idp_config.mtls_endpoint_aliases then
    endpoint = idp_config.mtls_endpoint_aliases[name]
  end
  
  if not endpoint then
    endpoint = idp_config[name]
  end

  return endpoint
end


function _M:request(url, opts, is_rp)
  local access_token = is_rp and self:get_access_token() or nil
  local nonce_name = is_rp and "rp_last_dpop_nonce" or "idp_last_dpop_nonce"
  local desigated_dpop = opts.headers["DPoP"]
  local res

  -- opts.headers["Host"] = opts.headers["Host"] or url:match("^https?://([^/]+)")

  -- retry if nonce is required and we are recieving one for the first time
  local retried = false
  ::retry::
  if self.using_dpop then
    opts.headers["DPoP"] = desigated_dpop or assert(self:generate_dpop_proof({
      method = opts.method,
      url = url,
    }, {
      access_token = access_token,
      nonce = self[nonce_name], -- if exists
    }), "failed to generate DPoP proof")
  end

  if self.dump_req then
    dump_request(url, opts, is_rp)
  end

  res = assert(self.http_client:request_uri(url, opts))
  self:update_cookies(res)

  if res.headers["DPoP-Nonce"] then
    self[nonce_name] = res.headers["DPoP-Nonce"]
  end

  if self.dump_req or (res.status >= 400 and self.dump_on_err) then
    dump_response(res, is_rp)
  end
  
  if (res.status == 400 or res.status == 401) and res.headers["DPoP-Nonce"] and not retried then
    if self.dump_req then
      print("retrying with nonce")
    end

    retried = true
    goto retry
  end

  return res
end


function _M:idp_request(url, opts, query_args, client_cred)
  opts.headers = opts.headers or {}
  local args = opts.args or {}

  if client_cred == "public" or "secret" then
    args.client_id = get_value_fallback("client_id", args, self)
  end

  if client_cred == "secret" then
    args.client_secret = get_value_fallback("client_secret", args, self)
  end
  
  local cookies = get_value_fallback("cookies", opts, self)
  if cookies then
    opts.headers["Cookie"] = cookies_to_header(cookies)
  end
  opts.cookies = nil

  local string_args = ngx.encode_args(args)

  if opts.args and opts.method == "GET" then
    url = append_query(url, string_args)
  else
    opts.headers["Content-Type"] = opts.headers["Content-Type"] or "application/x-www-form-urlencoded"
    opts.body = opts.body or string_args
  end

  if query_args then
    url = append_query(url, ngx.encode_args(query_args))
  end

  opts.args = nil

  return self:request(url, opts)
end


function _M:token_request(args, query_args)
  args = args or {}
  local token_endpoint = assert(self.token_endpoint, "no token_endpoint found")
  args.auth_method = get_value_fallback("auth_method", args, self) or "client_secret_basic"

  local res = self:idp_request(token_endpoint, {
    method = "POST",
    args = args,
  }, query_args, "secret", self.using_dpop and "header")

  assert(res.status == 200, "failed to fetch token: status " .. res.status)

  return res.body
end


function _M:get_token(args, query_args)
  local ret = cjson.decode(self:token_request(args, query_args))
  self.token_response = ret
  self.token_time = ngx.now()
  assert(ret.access_token, "no access_token found in token response")
  return ret
end


function _M:refresh_token()
  local token_response = assert(self.token_response, "no token_response found")
  local refresh_token = assert(token_response.refresh_token, "no refresh_token found in token_response")

  local refresh_expires_in = token_response.refresh_expires_in

  if refresh_expires_in and ngx.now() - self.token_time > refresh_expires_in then
    if self.auto_login then
      return self:login()
    else
      error("refresh token expired")
    end
  end

  return self:get_token({
    grant_type = "refresh_token",
    refresh_token = refresh_token,
  })
end


function _M:authenticate_request(args, query_args)
  args = args or {}
  local auth_endpoint = assert(self.authorization_endpoint, "no authorization_endpoint found")

  if args.client_secret == nil then
    args.client_secret = false
  end

  if args.redirect_uri == nil then
    args.redirect_uri = self.client_uri .. self.auth_callback_uri
  end

  args.response_type = args.response_type or "code"
  args.code_challenge_method = self.code_challenge_method or args.code_challenge_method or "S256"
  if args.code_challenge_method == "S256" then
    args.code_challenge = base64url_encode(jwa.S256(args.code_challenge))
  end

  local dpop_jkt

  if self.auth_dpop then
    dpop_jkt = jwks.compute_thumbprint(assert(self.client_jwk_public))
  end

  local res = self:idp_request(auth_endpoint, {
    method = "POST",
    args = args,
    dpop_jkt = dpop_jkt,
  }, query_args, "public")

  if res.status == 302 then
    local redirect_uri = assert(res.headers["Location"], "no redirect_uri found")
    local callback_args = redirect_uri:match(args.redirect_uri .. "%?([^?]+)")
    callback_args = ngx.decode_args(callback_args)
    if callback_args.error then
      error("authenticate failed: " .. (callback_args.error_description or callback_args.error))
    end

    return res
  end

  assert(res.status == 200, "failed to request for authentication: status " .. res.status)

  return res
end


-- auth_code flow
function _M:login(user_login_simulator)
  user_login_simulator = user_login_simulator or self.user_login_simulator

  local code_verifier
  if self.use_pkce then
    code_verifier = base64url_encode(utils.random_string(64))
  end

  local res = self:authenticate_request({
    grant_type = "authorization_code",
    code_challenge = code_verifier
  })

  local args = assert(user_login_simulator(self, res))
  local code = assert(args.code, "no code found")

  return self:get_token({
    grant_type = "authorization_code",
    code = code,
    code_verifier = code_verifier,
    auth_method = "code",
    redirect_uri = self.client_uri .. self.auth_callback_uri,
  })
end


local function extract_args(res)
  local redirect_uri = assert(res.headers["Location"], "no redirect_uri found")
  return ngx.decode_args(redirect_uri:match("%?(.*)"))
end


function _M.keycloak_login(client, res)
  if res.status == 302 then
    return extract_args(res)
  end

  local login_page = res.body
  local login_url = login_page:match('action="([^"]+)"')
  local login_args = {
    username = client.username,
    password = client.password,
  }

  local login_res = client:idp_request(login_url, {
    method = "POST",
    args = login_args,
  })

  if login_res.status == 200 then
    local failure_reason = login_res.body:match('<span id="input%-error"[^>]*>%s*([^<]-)%s*</span>')
    if failure_reason then
      error("login failed: " .. failure_reason)

    else
      error("login failed with unknown reason")
    end
  end

  assert(login_res.status == 302, "failed to login: status " .. login_res.status)

  return extract_args(login_res)
end


function _M.rp_request(self, url, opts)
  opts = opts or {}
  opts.headers = opts.headers or {}

  local access_token = self:get_access_token()

  opts.headers["Authorization"] =  opts.headers["Authorization"] or self.token_response.token_type .. " " .. access_token
  opts.headers["Cookie"] = cookies_to_header(self.cookies)
  opts.method = opts.method or "GET"

  if not url:match("^https?://") then
    url = self.client_uri .. url
  end

  return self:request(url, opts, true)
end


function _M.get_access_token(self)
  if not self.token_response then
    if self.auto_login then
      self:login()
    else
      error("no token")
    end
  end

  if ngx.now() - self.token_time > self.token_response.expires_in then
    self:refresh_token()
  end

  return assert(self.token_response.access_token)
end


return _M