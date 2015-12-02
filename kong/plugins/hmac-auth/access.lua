local cache = require "kong.tools.database_cache"
local stringy = require "stringy"
local responses = require "kong.tools.responses"
local constants = require "kong.constants"

local math_abs = math.abs
local ngx_time = ngx.time
local ngx_gmatch = ngx.re.gmatch
local ngx_decode_base64 = ngx.decode_base64
local ngx_parse_time = ngx.parse_http_time
local ngx_sha1 = ngx.hmac_sha1
local ngx_set_header = ngx.req.set_header
local ngx_set_headers = ngx.req.get_headers
local ngx_log = ngx.log

local split = stringy.split

local AUTHORIZATION = "authorization"
local PROXY_AUTHORIZATION = "proxy-authorization"
local DATE = "date"
local X_DATE = "x-date"
local SIGNATURE_NOT_VALID = "HMAC signature cannot be verified"

local _M = {}

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

local function create_hash(request, hmac_params, headers)
  local signing_string = ""
  local hmac_headers = hmac_params.hmac_headers
  local count = #hmac_headers

  for i = 1, count do
    local header = hmac_headers[i]
    local header_value = headers[header]

    if not header_value then
      if header == "request-line" then
        -- request-line in hmac headers list
        signing_string = signing_string..split(request.raw_header(), "\r\n")[1]
      else
        signing_string = signing_string..header..":"
      end
    else
      signing_string = signing_string..header..":".." "..header_value
    end
    if i < count then
      signing_string = signing_string.."\n"
    end
  end
  return ngx_sha1(hmac_params.secret, signing_string)
end

local function is_digest_equal(digest_1, digest_2)
  if #digest_1 ~= #digest_1 then
    return false
  end
      
  local result = true
  for i=1, #digest_1 do
    if digest_1:sub(i, i) ~= digest_2:sub(i, i) then
      result = false
    end  
  end    
  return result
end    

local function validate_signature(request, hmac_params, headers)
  local digest = create_hash(request, hmac_params, headers)
  if digest then
   return is_digest_equal(digest, ngx_decode_base64(hmac_params.signature))
  end
end

local function hmacauth_credential_key(username)
  return "hmacauth_credentials/"..username
end

local function load_credential(username)
  local credential
  if username then
      credential = cache.get_or_set(hmacauth_credential_key(username), function()
      local keys, err = dao.hmacauth_credentials:find_by_keys { username = username }
      local result
      if err then
        return responses.send_HTTP_INTERNAL_SERVER_ERROR(err)
      elseif #keys > 0 then
        result = keys[1]
      end
      return result
    end)
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

function _M.execute(conf)
  local headers = ngx_set_headers();
  -- If both headers are missing, return 401
  if not (headers[AUTHORIZATION] or headers[PROXY_AUTHORIZATION]) then
    return responses.send_HTTP_UNAUTHORIZED()
  end

  -- validate clock skew
  if not (validate_clock_skew(headers, X_DATE, conf.clock_skew) or validate_clock_skew(headers, DATE, conf.clock_skew)) then
      responses.send_HTTP_FORBIDDEN("HMAC signature cannot be verified, a valid date or x-date header is required for HMAC Authentication")
  end

  -- retrieve hmac parameter from Proxy-Authorization header
  local hmac_params = retrieve_hmac_fields(ngx.req, headers, PROXY_AUTHORIZATION, conf)
  -- Try with the authorization header
  if not hmac_params.username then
    hmac_params = retrieve_hmac_fields(ngx.req, headers, AUTHORIZATION, conf)
  end
  if not (hmac_params.username and hmac_params.signature) then
    responses.send_HTTP_FORBIDDEN(SIGNATURE_NOT_VALID)
  end

  -- validate signature
  local credential = load_credential(hmac_params.username)
  if not credential then
    responses.send_HTTP_FORBIDDEN(SIGNATURE_NOT_VALID)
  end
  hmac_params.secret = credential.secret
  if not validate_signature(ngx.req, hmac_params, headers) then
    return responses.send_HTTP_FORBIDDEN("HMAC signature does not match")
  end

  -- Retrieve consumer
  local consumer = cache.get_or_set(cache.consumer_key(credential.consumer_id), function()
    local result, err = dao.consumers:find_by_primary_key({ id = credential.consumer_id })
    if err then
      return responses.send_HTTP_INTERNAL_SERVER_ERROR(err)
    end
    return result
  end)

  ngx_set_header(constants.HEADERS.CONSUMER_ID, consumer.id)
  ngx_set_header(constants.HEADERS.CONSUMER_CUSTOM_ID, consumer.custom_id)
  ngx_set_header(constants.HEADERS.CONSUMER_USERNAME, consumer.username)
  ngx.req.set_header(constants.HEADERS.CREDENTIAL_USERNAME, credential.username)
  ngx.ctx.authenticated_credential = credential
end

return _M
