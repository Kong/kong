-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local cjson = require "cjson"
local http = require "resty.http"
local socket_url = require "socket.url"
local encode_args = require("kong.tools.http").encode_args
local ee_jwt = require "kong.enterprise_edition.jwt"
local enums = require "kong.enterprise_edition.dao.enums"

local lower = string.lower
local time = ngx.time

local tablex_sort = require("pl.tablex").sort


local _M = {}


-- Validates an email address
_M.validate_email = function(str)
    if str == nil then
      return nil, "missing"
    end

    if type(str) ~= "string" then
      return nil, "must be a string"
    end

    local at = str:find("@")

    if not at then
      return nil, "missing '@' symbol"
    end

    local last_at = str:find("[^%@]+$")

    if not last_at then
      return nil, "missing domain"
    end

    local local_part = str:sub(1, (last_at - 2)) -- Returns the substring before '@' symbol
    -- we werent able to split the email properly
    if local_part == nil or local_part == "" then
      return nil, "missing local-part"
    end

    local domain_part = str:sub(last_at, #str) -- Returns the substring after '@' symbol

    -- This may be redundant
    if domain_part == nil or domain_part == "" then
      return nil, "missing domain"
    end

    -- local part is maxed at 64 characters
    if #local_part > 64 then
      return nil, "local-part over 64 characters"
    end

    -- domains are maxed at 253 characters
    if #domain_part > 253 then
      return nil, "domain over 253 characters"
    end

    local quotes = local_part:find("[\"]")
    if type(quotes) == "number" and quotes > 1 then
      return nil, "local-part invalid quotes"
    end

    if local_part:find("%@+") and quotes == nil then
      return nil, "local-part invalid '@' character"
    end

    if not domain_part:find("%.") then
      return nil, "domain missing '.' character"
    end

    if domain_part:find("%.%.") then
      return nil, "domain cannot contain consecutive '.'"
    end
    if local_part:find("%.%.") then
      return nil, "local-part cannot contain consecutive '.'"
    end

    if not str:match('[%w]*[%p]*%@+[%w]*[%.]?[%w]*') then
      return nil, "invalid format"
    end

    return true
end


_M.check_case = function(value, consumer_t)
  -- for now, only applies to admins
  if consumer_t.type ~= enums.CONSUMERS.TYPE.ADMIN then
    return true
  end

  -- email must be case-insensitive, so we store it in a predictable case
  -- for querying. The /admins and /developers endpoints are responsible
  -- for converting user-entered data to lower-case. This is just a final
  -- check to make sure mixed-case doesn't make it into the db.
  if consumer_t.email and consumer_t.email ~= lower(consumer_t.email) then
    return false, "'email' must be lower case"
  end

  return true
end

_M.validate_reset_jwt = function(token_param)
  -- Decode jwt
  local jwt, err = ee_jwt.parse_JWT(token_param)
  if err then
    return nil, ee_jwt.INVALID_JWT
  end

  if not jwt.header or jwt.header.typ ~= "JWT" or jwt.header.alg ~= "HS256" then
    return nil, ee_jwt.INVALID_JWT
  end

  if not jwt.claims or not jwt.claims.exp then
    return nil, ee_jwt.INVALID_JWT
  end

  if jwt.claims.exp <= time() then
    return nil, ee_jwt.EXPIRED_JWT
  end

  if not jwt.claims.id then
    return nil, ee_jwt.INVALID_JWT
  end

  return jwt
end

-- Case insensitive lookup function, returns the value and the original key. Or
-- if not found nil and the search key
-- @usage -- sample usage
-- local test = { SoMeKeY = 10 }
-- print(lookup(test, "somekey"))  --> 10, "SoMeKeY"
-- print(lookup(test, "NotFound")) --> nil, "NotFound"
local function lookup(t, k)
  local ok = k
  if type(k) ~= "string" then
    return t[k], k
  else
    k = k:lower()
  end
  for key, value in pairs(t) do
    if tostring(key):lower() == k then
      return value, key
    end
  end
  return nil, ok
end

local function as_body(data, opts)
  local body = ""

  local headers = opts.headers or {}

  -- build body
  local content_type, content_type_name = lookup(headers, "Content-Type")
  content_type = content_type or ""
  local t_body_table = type(data) == "table"
  if string.find(content_type, "application/json") and t_body_table then
    body = cjson.encode(data)
  elseif string.find(content_type, "www-form-urlencoded", nil, true) and t_body_table then
    body = encode_args(data, true, opts.no_array_indexes)
  elseif string.find(content_type, "multipart/form-data", nil, true) and t_body_table then
    local form = data
    local boundary = "8fd84e9444e3946c"

    for k, v in pairs(form) do
      body = body .. "--" .. boundary .. "\r\nContent-Disposition: form-data; name=\"" .. k .. "\"\r\n\r\n" .. tostring(v) .. "\r\n"
    end

    if body ~= "" then
      body = body .. "--" .. boundary .. "--\r\n"
    end

    if not content_type:find("boundary=") then
      headers[content_type_name] = content_type .. "; boundary=" .. boundary
    end

  end

  return body
end

-- XXX: Ideally we make this a performant one
_M.request = function(url, opts)
  local opts = opts or {}
  local method = opts.method or "GET"
  local headers = opts.headers or {}
  local body = opts.body or nil
  local data = opts.data or nil

  if method == "GET" and data then
    url = url .. '?' .. encode_args(data)
  elseif method == "POST" or method == "PUT" or method == "PATCH" then
    if data and not body or #body == 0 then
      if not lookup(headers, "content-type") then
        headers["Content-Type"] = "multipart/form-data"
      end
      body = as_body(data, { headers = headers })
   end
  end

  if opts.sign_with and body then
    local sign_header = opts.sign_header or "X-Kong-Signature"
    -- sign with must be provided with a function that gets the body and
    -- returns the name of the hmac algorithm and the hmac of the body
    local alg, hmac = opts.sign_with(body)
    headers[sign_header] = alg .. "=" .. hmac
  end

  local client = http.new()
  local params = {
    method = method,
    body = body,
    headers = headers,
    ssl_verify = opts.ssl_verify or false,
  }

  return client:request_uri(url, params)
end

local function normalize_table(data)
  local hash
  for k, v in tablex_sort(data) do
    if type(v) == "table" then
      v = normalize_table(v)
    end
    if (type(v) == "string"
          or type(v) == "boolean"
          or type(v) == "number") then
      v = tostring(v)
      hash = hash and (hash .. ":" .. k .. ":" .. v) or (k .. ":" .. v)
    else
      hash = hash and (hash .. ":" .. k) or k
    end
  end
  return hash
end
_M.normalize_table = normalize_table

function _M.retrieve_admin_gui_url(admin_gui_urls)
  local admin_gui_urls = admin_gui_urls or kong.configuration.admin_gui_url
  local req_origin = ngx.req.get_headers()["Origin"]
  for _, gui_url in ipairs(admin_gui_urls) do
    local parsed_url = socket_url.parse(gui_url)
    local allowed_origin = parsed_url.scheme .. "://" .. parsed_url.authority
    if req_origin == allowed_origin then
      return gui_url
    end
  end
  return admin_gui_urls[1] or ""
end

function _M.retrieve_admin_gui_origin()
  local allowed_origins = kong.configuration.admin_gui_origin

  local function is_origin_allowed(req_origin)
    for _, allowed_origin in ipairs(allowed_origins) do
      if req_origin == allowed_origin then
        return true
      end
    end
    return false
  end

  local cors_origin, variant
  local req_origin = ngx.req.get_headers()["Origin"]

  if allowed_origins and #allowed_origins > 0 then
    if not is_origin_allowed(req_origin) then
      cors_origin = allowed_origins[1]
    end
    variant = cors_origin
  else
    cors_origin = req_origin or "*"
  end

  return cors_origin, variant
end


return _M
