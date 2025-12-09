-- +-------------------------------------------------------------+
--
--           Noma Security Guardrail Plugin for Kong
--                       https://noma.security
--
-- HTTP client module for communicating with Noma AI-DR service
--
-- +-------------------------------------------------------------+

local cjson = require("cjson.safe")
local http = require("resty.http")
local fmt = string.format

local _M = {}

-- API endpoints
_M.SCAN_ENDPOINT = "/ai-dr/v2/prompt/scan"
local DEFAULT_TOKEN_PATH = "/v1/oauth/token"

-- Default timeout in milliseconds
local DEFAULT_TIMEOUT_MS = 60000

-- Token cache (per-worker)
-- Key format: "{client_id}" -> { token = "...", expires_at = timestamp }
local token_cache = {}

-- Buffer time before token expiry to refresh (in seconds)
local TOKEN_REFRESH_BUFFER = 60


-------------------------------------------------------------------------------
-- Configuration Helpers
-------------------------------------------------------------------------------

--- Get client ID from config
-- @param conf Plugin configuration
-- @return string|nil Client ID
local function get_client_id(conf)
  if conf.client_id and conf.client_id ~= "" then
    return conf.client_id
  end
  return nil
end


--- Get client secret from config
-- @param conf Plugin configuration
-- @return string|nil Client secret
local function get_client_secret(conf)
  if conf.client_secret and conf.client_secret ~= "" then
    return conf.client_secret
  end
  return nil
end


--- Get token URL from config
-- @param conf Plugin configuration
-- @return string Token URL
local function get_token_url(conf)
  if conf.token_url and conf.token_url ~= "" then
    return conf.token_url
  end
  -- Default: {api_base}/v1/oauth/token
  return conf.api_base .. DEFAULT_TOKEN_PATH
end


--- Get application ID from config
-- @param conf Plugin configuration
-- @return string Application ID (defaults to "kong")
function _M.get_application_id(conf)
  if conf.application_id and conf.application_id ~= "" then
    return conf.application_id
  end
  return "kong"
end


-------------------------------------------------------------------------------
-- OAuth2 Token Management
-------------------------------------------------------------------------------

--- Fetch a new OAuth2 access token
-- @param conf Plugin configuration
-- @param http_opts HTTP options
-- @return string|nil Access token on success
-- @return string|nil Error message on failure
local function fetch_oauth_token(conf, http_opts)
  local client_id = get_client_id(conf)
  local client_secret = get_client_secret(conf)

  if not client_id or not client_secret then
    return nil, "client_id and client_secret are required for OAuth2 authentication"
  end

  local token_url = get_token_url(conf)

  local httpc = http.new()
  httpc:set_timeouts(http_opts.timeout or DEFAULT_TIMEOUT_MS)

  -- Frontegg API token request (JSON body with clientId and secret)
  local body = cjson.encode({
    clientId = client_id,
    secret = client_secret,
  })

  kong.log.debug("fetching OAuth token from: ", token_url)

  local res, err = httpc:request_uri(token_url, {
    method = "POST",
    headers = {
      ["Content-Type"] = "application/json",
    },
    body = body,
    ssl_verify = http_opts.ssl_verify,
  })

  if not res then
    return nil, "OAuth token request failed: " .. (err or "unknown error")
  end

  if res.status ~= 200 then
    return nil, fmt("OAuth token request returned status %d: %s", res.status, res.body or "")
  end

  local response_json, decode_err = cjson.decode(res.body)
  if not response_json then
    return nil, "failed to decode OAuth token response: " .. (decode_err or "unknown error")
  end

  -- Frontegg uses camelCase (accessToken)
  local access_token = response_json.accessToken
  if not access_token then
    return nil, "OAuth response missing access_token"
  end

  -- Cache the token (Frontegg uses expiresIn, standard OAuth uses expires_in)
  local expires_in = response_json.expiresIn or 3600
  token_cache[client_id] = {
    token = access_token,
    expires_at = ngx.now() + expires_in,
  }

  kong.log.debug("OAuth token cached, expires in: ", expires_in, "s")

  return access_token
end


--- Get OAuth2 access token (from cache or fetch new)
-- @param conf Plugin configuration
-- @param http_opts HTTP options
-- @return string|nil Access token on success
-- @return string|nil Error message on failure
local function get_oauth_token(conf, http_opts)
  local client_id = get_client_id(conf)
  if not client_id then
    return nil, "client_id is required for OAuth2 authentication"
  end

  -- Check cache
  local cached = token_cache[client_id]
  if cached and cached.expires_at > (ngx.now() + TOKEN_REFRESH_BUFFER) then
    return cached.token
  end

  -- Fetch new token
  return fetch_oauth_token(conf, http_opts)
end


--- Get authorization token via OAuth2
-- @param conf Plugin configuration
-- @param http_opts HTTP options
-- @return string|nil Bearer token on success
-- @return string|nil Error message on failure
local function get_auth_token(conf, http_opts)
  local client_id = get_client_id(conf)
  local client_secret = get_client_secret(conf)

  if client_id and client_secret then
    return get_oauth_token(conf, http_opts)
  end

  return nil  -- No authentication configured
end


-------------------------------------------------------------------------------
-- HTTP Options
-------------------------------------------------------------------------------

--- Build HTTP options from plugin configuration
-- @param conf Plugin configuration
-- @return table HTTP options for resty.http
function _M.build_http_opts(conf)
  local opts = {
    timeout = conf.http_timeout or DEFAULT_TIMEOUT_MS,
    ssl_verify = conf.https_verify,
  }

  -- Configure HTTP proxy
  if conf.http_proxy_host then
    opts.proxy_opts = opts.proxy_opts or {}
    opts.proxy_opts.http_proxy = fmt("http://%s:%d", conf.http_proxy_host, conf.http_proxy_port or 80)
  end

  -- Configure HTTPS proxy
  if conf.https_proxy_host then
    opts.proxy_opts = opts.proxy_opts or {}
    opts.proxy_opts.https_proxy = fmt("http://%s:%d", conf.https_proxy_host, conf.https_proxy_port or 443)
  end

  return opts
end


-------------------------------------------------------------------------------
-- Noma API
-------------------------------------------------------------------------------

--- Get request ID from header or Kong
-- @return string|nil Request ID
local function get_request_id()
  local id = kong.request.get_header("X-Request-ID")
  if id then
    return id
  end
  -- kong.request.get_id may not exist in all versions
  if kong.request.get_id then
    return kong.request.get_id()
  end
  return nil
end


--- Build request context for Noma API
-- @param conf Plugin configuration
-- @return table Noma context object
local function build_noma_context(conf)
  local request_id = get_request_id()

  return {
    applicationId = _M.get_application_id(conf),
    sessionId = request_id,
    requestId = request_id,
  }
end


--- Call Noma AI-DR scan API
-- @param payload table Request payload (must include 'input' field)
-- @param conf table Plugin configuration
-- @param http_opts table HTTP options (from build_http_opts)
-- @return table|nil Response JSON on success
-- @return string|nil Error message on failure
function _M.scan(payload, conf, http_opts)
  -- Get auth token
  local token, token_err = get_auth_token(conf, http_opts)
  if token_err then
    return nil, "authentication failed: " .. token_err
  end

  local httpc = http.new()
  httpc:set_timeouts(http_opts.timeout or DEFAULT_TIMEOUT_MS)

  local endpoint = conf.api_base .. _M.SCAN_ENDPOINT

  -- Build headers
  local headers = {
    ["Content-Type"] = "application/json",
  }

  if token then
    headers["Authorization"] = "Bearer " .. token
  end

  -- Add request tracking header
  local request_id = get_request_id()
  if request_id then
    headers["X-Noma-Request-ID"] = request_id
  end

  -- Add Noma context to payload
  payload["x-noma-context"] = build_noma_context(conf)

  -- Encode payload
  local body, encode_err = cjson.encode(payload)
  if not body then
    return nil, "failed to encode request payload: " .. (encode_err or "unknown error")
  end

  kong.log.debug("calling Noma API at: ", endpoint)

  -- Make request
  local res, err = httpc:request_uri(endpoint, {
    method = "POST",
    headers = headers,
    body = body,
    ssl_verify = http_opts.ssl_verify,
  })

  if not res then
    return nil, "Noma API request failed: " .. (err or "unknown error")
  end

  if res.status ~= 200 then
    return nil, fmt("Noma API returned status %d: %s", res.status, res.body or "")
  end

  -- Decode response
  local response_json, decode_err = cjson.decode(res.body)
  if not response_json then
    return nil, "failed to decode Noma API response: " .. (decode_err or "unknown error")
  end

  return response_json
end


-- Expose for testing
if _G._TEST then
  _M._get_oauth_token = get_oauth_token
  _M._fetch_oauth_token = fetch_oauth_token
  _M._get_auth_token = get_auth_token
  _M._token_cache = token_cache
end


return _M
