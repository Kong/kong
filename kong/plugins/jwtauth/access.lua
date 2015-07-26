local cache = require "kong.tools.database_cache"
local stringy = require "stringy"
local Multipart = require "multipart"
local responses = require "kong.tools.responses"
local constants = require "kong.constants"
local jwt = require "luajwt"
local basexx = require "basexx"

local CONTENT_TYPE = "content-type"
local CONTENT_LENGTH = "content-length"
local FORM_URLENCODED = "application/x-www-form-urlencoded"
local MULTIPART_DATA = "multipart/form-data"

local _M = {}

local function skip_authentication(headers)
  -- Skip upload request that expect a 100 Continue response
  return headers["expect"] and stringy.startswith(headers["expect"], "100")
end

-- Code taken from https://github.com/auth0/nginx-jwt
local function decode(secret)
  local s = secret
  -- convert from URL-safe Base64 to Base64
    local r = #s % 4
    if r == 2 then
        s = s .. "=="
    elseif r == 3 then
        s = s .. "="
    end
    s = string.gsub(s, "-", "+")
    s = string.gsub(s, "_", "/")

    -- convert from Base64 to UTF-8 string
    return basexx.from_base64(s)
end

local function get_key_from_query(key_name, request, conf)
  local key, parameters
  local found_in = {}


  local headers = request.get_headers()

  -- First, try in header
  if headers[key_name] ~= nil then
    found_in.header = true
    key = headers[key_name]
  end

  parameters = request.get_uri_args()

  -- Find in querystring
  if parameters[key_name] ~= nil then
    found_in.querystring = true
    key = parameters[key_name]
  -- If missing from querystring, try to get it from the body
  elseif request.get_headers()[CONTENT_TYPE] then
    -- Lowercase content-type for easier comparison
    local content_type = stringy.strip(string.lower(request.get_headers()[CONTENT_TYPE]))
    if stringy.startswith(content_type, FORM_URLENCODED) then
      -- Call ngx.req.read_body to read the request body first
      -- or turn on the lua_need_request_body directive to avoid errors.
      request.read_body()
      parameters = request.get_post_args()

      found_in.form = parameters[key_name] ~= nil
      key = parameters[key_name]
    elseif stringy.startswith(content_type, MULTIPART_DATA) then
      -- Call ngx.req.read_body to read the request body first
      -- or turn on the lua_need_request_body directive to avoid errors.
      request.read_body()

      local body = request.get_body_data()
      parameters = Multipart(body, content_type)

      local parameter = parameters:get(key_name)
      found_in.body = parameter ~= nil
      key = parameter and parameter.value or nil
    end
  end

  if conf.hide_credentials then
    if found_in.querystring then
      parameters[key_name] = nil
      request.set_uri_args(parameters)
    elseif found_in.header then
      request.clear_header(key_name)
    elseif found_in.form then
      parameters[key_name] = nil
      local encoded_args = ngx.encode_args(parameters)
      request.set_header(CONTENT_LENGTH, string.len(encoded_args))
      request.set_body_data(encoded_args)
    elseif found_in.body then
      parameters:delete(key_name)
      local new_data = parameters:tostring()
      request.set_header(CONTENT_LENGTH, string.len(new_data))
      request.set_body_data(new_data)
    end
  end
  return key
end

-- Fast lookup for credential retrieval depending on the type of the authentication
--
-- All methods must respect:
--
-- @param request ngx request object
-- @param {table} conf Plugin configuration (value property)
-- @return {string} public_key
-- @return {string} private_key
local function retrieve_credentials(request, conf)
  local username, token

  if conf.id_names then
    for _, id_name in ipairs(conf.id_names) do
      username = get_key_from_query(id_name, request, conf)
      if username then break end
    end
  end

  local authorization_header = request.get_headers()["authorization"]

  if authorization_header then
    local iterator, iter_err = ngx.re.gmatch(authorization_header, "\\s*[Bb]earer\\s*(.+)")
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
      token = m[1]
    end
  end

  if conf.hide_credentials then
    request.clear_header("authorization")
  end

  return username, token
end


function _M.execute(conf)
  if not conf or skip_authentication(ngx.req.get_headers()) then return end
  if not conf then return end

  local username, token = retrieve_credentials(ngx.req, conf)

  if not username or not token then
    ngx.ctx.stop_phases = true -- interrupt other phases of this request
    return responses.send_HTTP_FORBIDDEN("Invalid authentication credentials")
  end

  -- Retrieve consumer
  local consumer = cache.get_or_set(cache.consumer_key(username), function()
    local consumers, err = dao.consumers:find_by_keys { username = username }
    local result
    if err then
      return responses.send_HTTP_FORBIDDEN(err)
    elseif #consumers > 0 then
      result = consumers[1]
    end
    return result
  end)

  --Retrieve secret
  local credential

  -- Make sure we are not sending an empty table to find_by_keys
  credential = cache.get_or_set(cache.jwtauth_credential_key(consumer.id), function()
    local credentials, err = dao.jwtauth_credentials:find_by_keys { consumer_id = consumer.id }
    local result
    if err then
      return responses.send_HTTP_FORBIDDEN(err)
    elseif #credentials > 0 then
      result = credentials[1]
    end
    return result
  end)

  local secret = credential.secret

  if credential.secret_is_base64_encoded then
    secret = decode(secret)
  end

  local validate = true -- validate signature, exp and nbf (default: true)
  local profile, err = jwt.decode(token, secret, validate)
  if err then
    return responses.send_HTTP_FORBIDDEN(err)
  end

  -- what to do with profile
  credential.profile = profile

  ngx.req.set_header(constants.HEADERS.CONSUMER_ID, consumer.id)
  ngx.req.set_header(constants.HEADERS.CONSUMER_CUSTOM_ID, consumer.custom_id)
  ngx.req.set_header(constants.HEADERS.CONSUMER_USERNAME, consumer.username)
  ngx.ctx.authenticated_entity = credential
end

return _M
