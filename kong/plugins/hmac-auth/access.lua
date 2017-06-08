local utils = require "kong.tools.utils"
local cache = require "kong.tools.database_cache"
local responses = require "kong.tools.responses"
local constants = require "kong.constants"
local singletons = require "kong.singletons"

local math_abs = math.abs
local ngx_time = ngx.time
local ngx_gmatch = ngx.re.gmatch
local ngx_decode_base64 = ngx.decode_base64
local ngx_parse_time = ngx.parse_http_time
local ngx_sha1 = ngx.hmac_sha1
local ngx_set_header = ngx.req.set_header
local ngx_get_headers = ngx.req.get_headers
local ngx_log = ngx.log

local split = utils.split

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

local function validate_signature(request, hmac_params, headers)
  local digest = create_hash(request, hmac_params, headers)
  local sig = ngx_decode_base64(hmac_params.signature)

  return digest == sig
end

local function load_credential_into_memory(username)
  local keys, err = singletons.dao.hmacauth_credentials:find_all { username = username }
  if err then
    return nil, err
  end
  return keys[1]
end

local function load_credential(username)
  local credential, err
  if username then
    credential, err = cache.get_or_set(cache.hmacauth_credential_key(username),
                                  nil, load_credential_into_memory, username)
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

local function load_consumer_into_memory(consumer_id, anonymous)
  local result, err = singletons.dao.consumers:find { id = consumer_id }
  if not result then
    if anonymous and not err then
      err = 'anonymous consumer "'..consumer_id..'" not found'
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
  if not (hmac_params.username and hmac_params.signature) then
    return false, {status = 403, message = SIGNATURE_NOT_VALID}
  end

  -- validate signature
  local credential = load_credential(hmac_params.username)
  if not credential then
    return false, {status = 403, message = SIGNATURE_NOT_VALID}
  end
  hmac_params.secret = credential.secret
  if not validate_signature(ngx.req, hmac_params, headers) then
    return false, {status = 403, message = "HMAC signature does not match"}
  end

  -- Retrieve consumer
  local consumer, err = cache.get_or_set(cache.consumer_key(credential.consumer_id),
                   nil, load_consumer_into_memory, credential.consumer_id)
  if err then
    return responses.send_HTTP_INTERNAL_SERVER_ERROR(err)
  end

  set_consumer(consumer, credential)

  return true
end


function _M.execute(conf)

  if ngx.ctx.authenticated_credential and conf.anonymous ~= "" then
    -- we're already authenticated, and we're configured for using anonymous, 
    -- hence we're in a logical OR between auth methods and we're already done.
    return
  end

  local ok, err = do_authentication(conf)
  if not ok then
    if conf.anonymous ~= "" then
      -- get anonymous user
      local consumer, err = cache.get_or_set(cache.consumer_key(conf.anonymous),
                       nil, load_consumer_into_memory, conf.anonymous, true)
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
