local utils = require "kong.tools.utils"
local responses = require "kong.tools.responses"
local constants = require "kong.constants"
local openssl_hmac = require "openssl.hmac"
local resty_sha256 = require "resty.sha256"

local math_abs = math.abs
local ngx_time = ngx.time
local ngx_gmatch = ngx.re.gmatch
local ngx_decode_base64 = ngx.decode_base64
local ngx_encode_base64 = ngx.encode_base64
local ngx_parse_time = ngx.parse_http_time
local ngx_set_header = ngx.req.set_header
local ngx_get_headers = ngx.req.get_headers
local ngx_log = ngx.log
local req_read_body = ngx.req.read_body
local req_get_body_data = ngx.req.get_body_data
local ngx_hmac_sha1 = ngx.hmac_sha1
local split = utils.split
local fmt = string.format
local ipairs = ipairs

local AUTHORIZATION = "authorization"
local PROXY_AUTHORIZATION = "proxy-authorization"
local DATE = "date"
local X_DATE = "x-date"
local DIGEST = "digest"
local SIGNATURE_NOT_VALID = "HMAC signature cannot be verified"
local SIGNATURE_NOT_SAME = "HMAC signature does not match"

local new_tab
do
  local ok
  ok, new_tab = pcall(require, "table.new")
  if not ok then
    new_tab = function() return {} end
  end
end


local _M = {}

local hmac = {
  ["hmac-sha1"] = function(secret, data)
    return ngx_hmac_sha1(secret, data)
  end,
  ["hmac-sha256"] = function(secret, data)
    return openssl_hmac.new(secret, "sha256"):final(data)
  end,
  ["hmac-sha384"] = function(secret, data)
    return openssl_hmac.new(secret, "sha384"):final(data)
  end,
  ["hmac-sha512"] = function(secret, data)
    return openssl_hmac.new(secret, "sha512"):final(data)
  end
}

local function list_as_set(list)
  local set = new_tab(0, #list)
  for _, v in ipairs(list) do
    set[v] = true
  end

  return set
end

local function validate_params(params, conf)
  -- check username and signature are present
  if not params.username and params.signature then
    return nil, "username or signature missing"
  end

  -- check enforced headers are present
  if conf.enforce_headers and #conf.enforce_headers >= 1 then
    local enforced_header_set = list_as_set(conf.enforce_headers)
    if params.hmac_headers then
      for _, header in ipairs(params.hmac_headers) do
        enforced_header_set[header] = nil
      end
    end
    for _, header in ipairs(conf.enforce_headers) do
      if enforced_header_set[header] then
        return nil, "enforced header not used for signature creation"
      end
    end
  end

  -- check supported alorithm used
  for _, algo in ipairs(conf.algorithms) do
    if algo == params.algorithm then
      return true
    end
  end

  return nil, fmt("algorithm %s not supported", params.algorithm)
end

local function retrieve_hmac_fields(request, headers, header_name, conf)
  local hmac_params = {}
  local authorization_header = headers[header_name]
  -- parse the header to retrieve hamc parameters
  if authorization_header then
    local iterator, iter_err = ngx_gmatch(authorization_header, "\\s*[Hh]mac\\s*username=\"(.+)\",\\s*algorithm=\"(.+)\",\\s*headers=\"(.+)\",\\s*signature=\"(.+)\"")
    if not iterator then
      ngx_log(ngx.ERR, iter_err)
      return
    end

    local m, err = iterator()
    if err then
      ngx_log(ngx.ERR, err)
      return
    end

    if m and #m >= 4 then
      hmac_params.username = m[1]
      hmac_params.algorithm = m[2]
      hmac_params.hmac_headers = split(m[3], " ")
      hmac_params.signature = m[4]
    end
  end

  if conf.hide_credentials then
    request.clear_header(header_name)
  end

  return hmac_params
end

-- plugin assumes the request parameters being used for creating
-- signature by client are not changed by core or any other plugin
local function create_hash(request, request_uri, hmac_params, headers)
  local signing_string = ""
  local hmac_headers = hmac_params.hmac_headers
  local count = #hmac_headers

  for i = 1, count do
    local header = hmac_headers[i]
    local header_value = headers[header]

    if not header_value then
      if header == "request-line" then
        -- request-line in hmac headers list
        local request_line = fmt("%s %s HTTP/%s", ngx.req.get_method(),
                                 request_uri, ngx.req.http_version())
        signing_string = signing_string .. request_line
      else
        signing_string = signing_string .. header .. ":"
      end
    else
      signing_string = signing_string .. header .. ":" .. " " .. header_value
    end
    if i < count then
      signing_string = signing_string .. "\n"
    end
  end
  return hmac[hmac_params.algorithm](hmac_params.secret, signing_string)
end

local function validate_signature(request, hmac_params, headers)
  local signature_1 = create_hash(request, ngx.var.request_uri, hmac_params, headers)
  local signature_2 = ngx_decode_base64(hmac_params.signature)

  if signature_1 == signature_2 then
    return true
  end

  -- DEPRECATED BY: https://github.com/Kong/kong/pull/3339
  local signature_1_deprecated = create_hash(request, ngx.var.uri, hmac_params, headers)

  return signature_1_deprecated == signature_2
end

local function load_credential_into_memory(username)
  local key, err = kong.db.hmacauth_credentials:select_by_username(username)
  if err then
    return nil, err
  end
  return key
end

local function load_credential(username)
  local credential, err
  if username then
    local credential_cache_key = kong.db.hmacauth_credentials:cache_key(username)
    credential, err = kong.cache:get(credential_cache_key, nil,
                                     load_credential_into_memory,
                                     username)
  end

  if err then
    return responses.send_HTTP_INTERNAL_SERVER_ERROR(err)
  end

  return credential
end

local function validate_clock_skew(headers, date_header_name, allowed_clock_skew)
  local date = headers[date_header_name]
  if not date then
    return false
  end

  local requestTime = ngx_parse_time(date)
  if not requestTime then
    return false
  end

  local skew = math_abs(ngx_time() - requestTime)
  if skew > allowed_clock_skew then
    return false
  end
  return true
end

local function validate_body(digest_received)
  req_read_body()
  local body = req_get_body_data()

  if not digest_received then
    -- if there is no digest and no body, it is ok
    return not body
  end

  local sha256 = resty_sha256:new()
  sha256:update(body or '')
  local digest_created = "SHA-256=" .. ngx_encode_base64(sha256:final())

  return digest_created == digest_received
end

local function load_consumer_into_memory(consumer_id, anonymous)
  local result, err = kong.db.consumers:select { id = consumer_id }
  if not result then
    if anonymous and not err then
      err = 'anonymous consumer "' .. consumer_id .. '" not found'
    end
    return nil, err
  end
  return result
end

local function set_consumer(consumer, credential)
  ngx_set_header(constants.HEADERS.CONSUMER_ID, consumer.id)
  ngx_set_header(constants.HEADERS.CONSUMER_CUSTOM_ID, consumer.custom_id)
  ngx_set_header(constants.HEADERS.CONSUMER_USERNAME, consumer.username)
  ngx.ctx.authenticated_consumer = consumer
  if credential then
    ngx_set_header(constants.HEADERS.CREDENTIAL_USERNAME, credential.username)
    ngx.ctx.authenticated_credential = credential
    ngx_set_header(constants.HEADERS.ANONYMOUS, nil) -- in case of auth plugins concatenation
  else
    ngx_set_header(constants.HEADERS.ANONYMOUS, true)
  end

end

local function do_authentication(conf)
  local headers = ngx_get_headers()
  -- If both headers are missing, return 401
  if not (headers[AUTHORIZATION] or headers[PROXY_AUTHORIZATION]) then
    return false, {status = 401}
  end

  -- validate clock skew
  if not (validate_clock_skew(headers, X_DATE, conf.clock_skew) or validate_clock_skew(headers, DATE, conf.clock_skew)) then
    return false, {status = 403, message = "HMAC signature cannot be verified, a valid date or x-date header is required for HMAC Authentication"}
  end

  -- retrieve hmac parameter from Proxy-Authorization header
  local hmac_params = retrieve_hmac_fields(ngx.req, headers, PROXY_AUTHORIZATION, conf)

  -- Try with the authorization header
  if not hmac_params.username then
    hmac_params = retrieve_hmac_fields(ngx.req, headers, AUTHORIZATION, conf)
  end

  local ok, err = validate_params(hmac_params, conf)
  if not ok then
    ngx_log(ngx.DEBUG, err)
    return false, {status = 403, message = SIGNATURE_NOT_VALID}
  end

  -- validate signature
  local credential = load_credential(hmac_params.username)
  if not credential then
    ngx_log(ngx.DEBUG, "failed to retrieve credential for ", hmac_params.username)
    return false, {status = 403, message = SIGNATURE_NOT_VALID}
  end
  hmac_params.secret = credential.secret

  if not validate_signature(ngx.req, hmac_params, headers) then
    return false, { status = 403, message = SIGNATURE_NOT_SAME }
  end

  -- If request body validation is enabled, then verify digest.
  if conf.validate_request_body and not validate_body(headers[DIGEST]) then
    ngx_log(ngx.DEBUG, "digest validation failed")
    return false, { status = 403, message = SIGNATURE_NOT_SAME }
  end

  -- Retrieve consumer
  local consumer_cache_key = kong.db.consumers:cache_key(credential.consumer.id)
  local consumer, err      = kong.cache:get(consumer_cache_key, nil,
                                            load_consumer_into_memory,
                                            credential.consumer.id)
  if err then
    return responses.send_HTTP_INTERNAL_SERVER_ERROR(err)
  end

  set_consumer(consumer, credential)

  return true
end


function _M.execute(conf)

  if ngx.ctx.authenticated_credential and conf.anonymous then
    -- we're already authenticated, and we're configured for using anonymous,
    -- hence we're in a logical OR between auth methods and we're already done.
    return
  end

  local ok, err = do_authentication(conf)
  if not ok then
    if conf.anonymous then
      -- get anonymous user
      local consumer_cache_key = kong.db.consumers:cache_key(conf.anonymous)
      local consumer, err      = kong.cache:get(consumer_cache_key, nil,
                                                load_consumer_into_memory,
                                                conf.anonymous, true)
      if err then
        return responses.send_HTTP_INTERNAL_SERVER_ERROR(err)
      end
      set_consumer(consumer, nil)
    else
      return responses.send(err.status, err.message)
    end
  end
end


return _M
