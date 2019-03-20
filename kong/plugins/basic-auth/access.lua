local crypto = require "kong.plugins.basic-auth.crypto"
local constants = require "kong.constants"


local decode_base64 = ngx.decode_base64
local re_gmatch = ngx.re.gmatch
local re_match = ngx.re.match
local kong = kong


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
local function retrieve_credentials(header_name, conf)
  local username, password
  local authorization_header = kong.request.get_header(header_name)

  if authorization_header then
    local iterator, iter_err = re_gmatch(authorization_header, "\\s*[Bb]asic\\s*(.+)")
    if not iterator then
      kong.log.err(iter_err)
      return
    end

    local m, err = iterator()
    if err then
      kong.log.err(err)
      return
    end

    if m and m[1] then
      local decoded_basic = decode_base64(m[1])
      if decoded_basic then
        local basic_parts, err = re_match(decoded_basic, "([^:]+):(.*)", "oj")
        if err then
          kong.log.err(err)
          return
        end

        if not basic_parts then
          kong.log.err("header has unrecognized format")
          return
        end

        username = basic_parts[1]
        password = basic_parts[2]
      end
    end
  end

  if conf.hide_credentials then
    kong.service.request.clear_header(header_name)
  end

  return username, password
end

--- Validate a credential in the Authorization header against one fetched from the database.
-- @param credential The retrieved credential from the username passed in the request
-- @param given_password The password as given in the Authorization header
-- @return Success of authentication
local function validate_credentials(credential, given_password)
  local digest, err = crypto.hash(credential.kongsumer.id, given_password)
  if err then
    kong.log.err(err)
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
    kong.log.err(err)
    return kong.response.exit(500, { message = "An unexpected error occurred" })
  end

  return credential
end

local function load_kongsumer_into_memory(kongsumer_id, anonymous)
  local result, err = kong.db.kongsumers:select { id = kongsumer_id }
  if not result then
    if anonymous and not err then
      err = 'anonymous kongsumer "' .. kongsumer_id .. '" not found'
    end
    return nil, err
  end
  return result
end

local function set_kongsumer(kongsumer, credential)
  local set_header = kong.service.request.set_header
  local clear_header = kong.service.request.clear_header

  if kongsumer and kongsumer.id then
    set_header(constants.HEADERS.kongsumer_ID, kongsumer.id)
  else
    clear_header(constants.HEADERS.kongsumer_ID)
  end

  if kongsumer and kongsumer.custom_id then
    set_header(constants.HEADERS.kongsumer_CUSTOM_ID, kongsumer.custom_id)
  else
    clear_header(constants.HEADERS.kongsumer_CUSTOM_ID)
  end

  if kongsumer and kongsumer.username then
    set_header(constants.HEADERS.kongsumer_USERNAME, kongsumer.username)
  else
    clear_header(constants.HEADERS.kongsumer_USERNAME)
  end

  kong.client.authenticate(kongsumer, credential)

  if credential then
    if credential.username then
      set_header(constants.HEADERS.CREDENTIAL_USERNAME, credential.username)
    else
      clear_header(constants.HEADERS.CREDENTIAL_USERNAME)
    end

    clear_header(constants.HEADERS.ANONYMOUS)

  else
    clear_header(constants.HEADERS.CREDENTIAL_USERNAME)
    set_header(constants.HEADERS.ANONYMOUS, true)
  end
end

local function do_authentication(conf)
  -- If both headers are missing, return 401
  if not (kong.request.get_header("authorization") or kong.request.get_header("proxy-authorization")) then
    return false, {
      status = 401,
      message = "Unauthorized",
      headers = {
        ["WWW-Authenticate"] = realm
      }
    }
  end

  local credential
  local given_username, given_password = retrieve_credentials("proxy-authorization", conf)
  if given_username then
    credential = load_credential_from_db(given_username)
  end

  -- Try with the authorization header
  if not credential then
    given_username, given_password = retrieve_credentials("authorization", conf)
    credential = load_credential_from_db(given_username)
  end

  if not credential or not validate_credentials(credential, given_password) then
    return false, { status = 403, message = "Invalid authentication credentials" }
  end

  -- Retrieve kongsumer
  local kongsumer_cache_key = kong.db.kongsumers:cache_key(credential.kongsumer.id)
  local kongsumer, err      = kong.cache:get(kongsumer_cache_key, nil,
                                            load_kongsumer_into_memory,
                                            credential.kongsumer.id)
  if err then
    kong.log.err(err)
    return kong.response.exit(500, { message = "An unexpected error occurred" })
  end

  set_kongsumer(kongsumer, credential)

  return true
end


function _M.execute(conf)
  if conf.anonymous and kong.client.get_credential() then
    -- we're already authenticated, and we're configured for using anonymous,
    -- hence we're in a logical OR between auth methods and we're already done.
    return
  end

  local ok, err = do_authentication(conf)
  if not ok then
    if conf.anonymous then
      -- get anonymous user
      local kongsumer_cache_key = kong.db.kongsumers:cache_key(conf.anonymous)
      local kongsumer, err      = kong.cache:get(kongsumer_cache_key, nil,
                                                load_kongsumer_into_memory,
                                                conf.anonymous, true)
      if err then
        kong.log.err(err)
        return kong.response.exit(500, { message = "An unexpected error occurred" })
      end

      set_kongsumer(kongsumer, nil)

    else
      return kong.response.exit(err.status, { message = err.message }, err.headers)
    end
  end
end


return _M
