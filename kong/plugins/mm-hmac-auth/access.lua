local cache = require "kong.tools.database_cache"
local stringy = require "stringy"
local responses = require "kong.tools.responses"
local constants = require "kong.constants"

local math_abs = math.abs
local ngx_time = ngx.time
local ngx_gmatch = ngx.re.gmatch
local ngx_decode_base64 = ngx.decode_base64
local ngx_encode_base64 = ngx.encode_base64
local ngx_parse_time = ngx.parse_http_time
local ngx_sha1 = ngx.hmac_sha1
local ngx_set_header = ngx.req.set_header

local AUTHORIZATION = "authorization"
local DATE = "date"
local SIGNATURE_NOT_VALID = "HMAC signature cannot be verified"

local _M = {}

local function retrieve_hmac_fields(request, header_name, conf)
  local username, signature
  local authorization_header = request.get_headers()[header_name]
  ngx.log(ngx.ERR, "MM: Authorization header is " .. authorization_header)
  if authorization_header then
    -- Authorization: MM-1 <API Key> <HMAC>
    local iterator, iter_err = ngx_gmatch(authorization_header, "\\s*MM-1\\s*(.+)")
    if not iterator then
      ngx.log(ngx.ERR, iter_err)
      return
    end

    local m, err = iterator()
    if err then
      ngx.log(ngx.ERR, err)
      return
    end

    if m and table.getn(m) > 0 then
      local hmac_fields = stringy.split(m[1], " ")
      if hmac_fields and #hmac_fields == 2 then
        username = hmac_fields[1]
        signature = ngx_decode_base64(hmac_fields[2])
      end
    end
  end

  if conf.hide_credentials then
    request.clear_header(header_name)
  end

  return username, signature, "HMAC-SHA1"
end

local function validate_signature(request, secret, signature, algorithm, defaultClockSkew)
  -- validate clock skew
  local method = request.get_method()
  local contentType = request.get_headers()["Content-Type"]
  if not contentType then
    contentType = ""
  end
  local path = ngx.var.uri
  request.read_body()
  local body = request.get_body_data()
  if not body then
      body = ""
  end
  local date = request.get_headers()[DATE]
  local requestTime = ngx_parse_time(date)
  if requestTime == nil then
    responses.send_HTTP_UNAUTHORIZED(SIGNATURE_NOT_VALID)
  end

  local skew = math_abs(ngx_time() - requestTime)
  if skew > defaultClockSkew then
    responses.send_HTTP_UNAUTHORIZED("HMAC signature expired")
  end

  local stringToSign = method .. "\n" .. contentType .. "\n" .. date .. "\n" ..path.. "\n" .. body
  ngx.log(ngx.ERR, "MM: String to sign: "..stringToSign)
  -- validate signature
  local digest = ngx_sha1(secret.secret, stringToSign)
  ngx.log(ngx.ERR, "MM: Digest: "..ngx_encode_base64(digest))
  ngx.log(ngx.ERR, "MM: Signature: "..ngx_encode_base64(signature))
  if digest then
    ngx.log(ngx.ERR, "MM: Comparing....")
    return ngx_encode_base64(digest) == ngx_encode_base64(signature)
  end
end

local function hmacauth_credential_key(username)
  return "mm_hmacauth_credentials/"..username
end

local function load_secret(username)
  local secret
  if username then
      secret = cache.get_or_set(hmacauth_credential_key(username), function()
      ngx.log(ngx.ERR, "MM: KEY NOT FOUND")
      local keys, err = dao.mm_hmacauth_credentials:find_by_keys { username = username }
      local result
      if err then
        return responses.send_HTTP_INTERNAL_SERVER_ERROR(err)
      elseif #keys > 0 then
        result = keys[1]
      end
      return result
    end)
  end
  return secret
end

function _M.execute(conf)
  -- If both headers are missing, return 401
  if not ngx.req.get_headers()[AUTHORIZATION] then
    ngx.ctx.stop_phases = true
    return responses.send_HTTP_UNAUTHORIZED()
  end

  local username, signature, algorithm = retrieve_hmac_fields(ngx.req, AUTHORIZATION, conf)

  if not (username and signature) then
    responses.send_HTTP_FORBIDDEN(SIGNATURE_NOT_VALID)
  end
  ngx.log(ngx.ERR, "MM: Username "..username)
  ngx.log(ngx.ERR, "MM: Signature "..signature)
  ngx.log(ngx.ERR, "MM: Algorithm "..algorithm)

  local secret = load_secret(username)

  if not validate_signature(ngx.req, secret, signature, algorithm, conf.clock_skew) then
    ngx.ctx.stop_phases = true -- interrupt other phases of this request
    return responses.send_HTTP_FORBIDDEN("HMAC signature does not match")
  end

  -- Retrieve consumer
  local consumer = cache.get_or_set(cache.consumer_key(secret.consumer_id), function()
    local result, err = dao.consumers:find_by_primary_key({ id = secret.consumer_id })
    if err then
      return responses.send_HTTP_INTERNAL_SERVER_ERROR(err)
    end
    return result
  end)

  ngx_set_header(constants.HEADERS.CONSUMER_ID, consumer.id)
  ngx_set_header(constants.HEADERS.CONSUMER_CUSTOM_ID, consumer.custom_id)
  ngx_set_header(constants.HEADERS.CONSUMER_USERNAME, consumer.username)
  ngx.ctx.authenticated_entity = secret
end

return _M
