local crypto = require "kong.plugins.basic-auth.crypto"
local constants = require "kong.constants"
local responses = require "kong.tools.responses"

local ngx_set_header = ngx.req.set_header
local ngx_get_headers = ngx.req.get_headers
local ngx_re_match = ngx.re.match

local realm = 'Basic realm="' .. _KONG._NAME .. '"'

local _M = {}

-- Fast lookup for credential retrieval depending on the type of the authentication
--
-- All methods must respect:
--
-- @param request ngx request object
-- @param {table} conf Plugin config
-- @return {string} public_key
-- @return {string} private_key
local function retrieve_credentials(request, header_name, conf)
  local username, password
  local authorization_header = request.get_headers()[header_name]

  if authorization_header then
    local iterator, iter_err = ngx.re.gmatch(authorization_header, "\\s*[Bb]asic\\s*(.+)")
    if not iterator then
      ngx.log(ngx.ERR, iter_err)
      return
    end

    local m, err = iterator()
    if err then
      ngx.log(ngx.ERR, err)
      return
    end

    if m and m[1] then
      local decoded_basic = ngx.decode_base64(m[1])
      if decoded_basic then
        local basic_parts, err = ngx_re_match(decoded_basic,
                                              "([^:]+):(.*)", "oj")
        if err then
          ngx.log(ngx.ERR, err)
          return
        end

        if not basic_parts then
          ngx.log(ngx.ERR, "[basic-auth] header has unrecognized format")
          return
        end

        username = basic_parts[1]
        password = basic_parts[2]
      end
    end
  end

  if conf.hide_credentials then
    request.clear_header(header_name)
  end

  return username, password
end

--- Validate a credential in the Authorization header against one fetched from the database.
-- @param credential The retrieved credential from the username passed in the request
-- @param given_password The password as given in the Authorization header
-- @return Success of authentication
local function validate_credentials(credential, given_password)
  local digest, err = crypto.encrypt(credential.consumer.id, given_password)
  if err then
    ngx.log(ngx.ERR, "[basic-auth]  " .. err)
  end
  return credential.password == digest
end

local function load_credential_into_memory(username)
  local credential, err = kong.db.basicauth_credentials:select_by_username(username)
  if err then
    return nil, err
  end
  return credential
end

local function load_credential_from_db(username)
  if not username then
    return
  end

  local credential_cache_key = kong.db.basicauth_credentials:cache_key(username)
  local credential, err      = kong.cache:get(credential_cache_key, nil,
                                              load_credential_into_memory,
                                              username)
  if err then
    return responses.send_HTTP_INTERNAL_SERVER_ERROR(err)
  end
  return credential
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
  -- If both headers are missing, return 401
  local headers = ngx_get_headers()
  if not (headers["authorization"] or headers["proxy-authorization"]) then
    ngx.header["WWW-Authenticate"] = realm
    return false, {status = 401}
  end

  local credential
  local given_username, given_password = retrieve_credentials(ngx.req, "proxy-authorization", conf)
  if given_username then
    credential = load_credential_from_db(given_username)
  end

  -- Try with the authorization header
  if not credential then
    given_username, given_password = retrieve_credentials(ngx.req, "authorization", conf)
    credential = load_credential_from_db(given_username)
  end

  if not credential or not validate_credentials(credential, given_password) then
    return false, {status = 403, message = "Invalid authentication credentials"}
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

  if ngx.ctx.authenticated_credential and conf.anonymous ~= "" then
    -- we're already authenticated, and we're configured for using anonymous,
    -- hence we're in a logical OR between auth methods and we're already done.
    return
  end

  local ok, err = do_authentication(conf)
  if not ok then
    if conf.anonymous ~= "" then
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
