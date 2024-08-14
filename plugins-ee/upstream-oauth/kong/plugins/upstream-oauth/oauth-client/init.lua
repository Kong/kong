-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local jwt          = require "resty.jwt"
local uuid         = require("kong.tools.utils").uuid
local table_merge  = require("kong.tools.utils").table_merge
local util         = require("kong.plugins.upstream-oauth.oauth-client.util")
local constants    = require("kong.plugins.upstream-oauth.oauth-client.constants")
local http         = require "resty.http"
local json         = require "cjson.safe"
local ngx          = ngx
local setmetatable = setmetatable
local time         = ngx.time
local _M           = { constants = constants }

function _M.new(client_opts, oauth_cfg)
  local headers = table_merge(
    oauth_cfg.token_headers,
    {
      ["Content-Type"] = "application/x-www-form-urlencoded"
    }
  )
  local body = {}

  -- Set additional post arguments from the config first
  for key, value in pairs(oauth_cfg.token_post_args) do
    util.set_optional_str(body, key, value)
  end

  -- Set client_id & client_secret into either the body or headers as per config
  if client_opts.auth_method == constants.AUTH_TYPE_CLIENT_SECRET_POST then
    util.set_optional_str(body, "client_id", oauth_cfg.client_id)
    util.set_optional_str(body, "client_secret", oauth_cfg.client_secret)
  elseif client_opts.auth_method == constants.AUTH_TYPE_CLIENT_SECRET_JWT then
    local jwt_data = {
      header = {
        typ = "JWT",
        alg = client_opts.client_secret_jwt_alg
      },
      payload = {
        iss = oauth_cfg.client_id,
        sub = oauth_cfg.client_id,
        aud = oauth_cfg.token_endpoint,
        jti = uuid(),
        nbf = time(),
        exp = time() + 60,
      }
    }
    local jwt_token = jwt:sign(oauth_cfg.client_secret, jwt_data)
    body.client_assertion_type = "urn:ietf:params:oauth:client-assertion-type:jwt-bearer"
    body.client_assertion = jwt_token
  elseif client_opts.auth_method == constants.AUTH_TYPE_CLIENT_SECRET_BASIC then
    headers["Authorization"] = "Basic " .. ngx.encode_base64(oauth_cfg.client_id .. ":" .. oauth_cfg.client_secret)
  end

  -- Set additional post arguments
  util.set_optional_str(body, "grant_type", oauth_cfg.grant_type)
  util.set_optional_str(body, "username", oauth_cfg.username)
  util.set_optional_str(body, "password", oauth_cfg.password)
  util.set_optional_arr(body, "scope", oauth_cfg.scopes)
  util.set_optional_arr(body, "audience", oauth_cfg.audience)

  -- Encode the body and set the content length
  local encoded_body = ngx.encode_args(body)
  headers["Content-Length"] = #encoded_body

  -- HTTP/HTTPS proxy options
  local proxy_opts = {}
  util.set_optional_str(proxy_opts, "http_proxy", client_opts.http_proxy)
  util.set_optional_str(proxy_opts, "http_proxy_authorization", client_opts.http_proxy_authorization)
  util.set_optional_str(proxy_opts, "https_proxy", client_opts.https_proxy)
  util.set_optional_str(proxy_opts, "https_proxy_authorization", client_opts.https_proxy_authorization)
  util.set_optional_str(proxy_opts, "no_proxy", client_opts.no_proxy)

  -- Set up the HTTP client
  local httpc = http.new()
  httpc:set_timeout(client_opts.timeout)

  local self = {
    httpc = httpc,
    endpoint = oauth_cfg.token_endpoint,
    params = {
      method = "POST",
      headers = headers,
      body = encoded_body,
      version = client_opts.http_version,
      keepalive = client_opts.keep_alive,
      ssl_verify = client_opts.ssl_verify,
      proxy_opts = proxy_opts
    }
  }

  return setmetatable(self, {
    __index = _M,
  })
end

--- Retrieve a token from the IdP token endpoint
-- @return string the token response body, or nil on error
-- @return string the error message if an error occurred, or nil on success
function _M:get_token()
  -- Make the HTTP request to the IdP token endpoint
  local res, err = self.httpc:request_uri(self.endpoint, self.params)

  -- Check the response status
  if not res then
    return nil, "Failed to make request to IdP: " .. err
  end

  if (res.status >= 400) then
    local msg = "Unexpected response from IdP. Status: " .. res.status
        .. " Body: " .. res.body
    return nil, msg
  end

  -- Parse the response body as JSON
  local token_response, decode_err = json.decode(res.body)
  if decode_err then
    local msg = "Failed to decode response from IdP. Reason: " .. decode_err
        .. " Response: " .. res.body
    return nil, msg
  end

  if not token_response or not token_response.access_token then
    local msg = "Unable to retrieve access token from IdP response."
        .. " Response: " .. res.body
    return nil, msg
  end

  return token_response, nil
end

return _M
