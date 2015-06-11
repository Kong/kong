local cache = require "kong.tools.database_cache"
local stringy = require "stringy"
local responses = require "kong.tools.responses"
local constants = require "kong.constants"

local _M = {}

local function skip_authentication(headers)
  -- Skip upload request that expect a 100 Continue response
  return headers["expect"] and stringy.startswith(headers["expect"], "100")
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
  local username, password
  local authorization_header = request.get_headers()["authorization"]

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

    if m and table.getn(m) > 0 then
      local decoded_basic = ngx.decode_base64(m[1])
      local basic_parts = stringy.split(decoded_basic, ":")
      username = basic_parts[1]
      password = basic_parts[2]
    end
  end

  if conf.hide_credentials then
    request.clear_header("authorization")
  end

  return username, password
end

-- Fast lookup for credential validation depending on the type of the authentication
--
-- All methods must respect:
--
-- @param {table} credential The retrieved credential from the username passed in the request
-- @param {string} username
-- @param {string} password
-- @return {boolean} Success of authentication
local function validate_credentials(credential, username, password)
  if credential then
    -- TODO: No encryption yet
    return credential.password == password
  end
end

function _M.execute(conf)
  if not conf or skip_authentication(ngx.req.get_headers()) then return end
  if not conf then return end

  local username, password = retrieve_credentials(ngx.req, conf)
  local credential

  -- Make sure we are not sending an empty table to find_by_keys
  if username then
    credential = cache.get_or_set(cache.basicauth_credential_key(username), function()
      local credentials, err = dao.basicauth_credentials:find_by_keys { username = username }
      local result
      if err then
        return responses.send_HTTP_INTERNAL_SERVER_ERROR(err)
      elseif #credentials > 0 then
        result = credentials[1]
      end
      return result
    end)
  end

  if not validate_credentials(credential, username, password) then
    ngx.ctx.stop_phases = true -- interrupt other phases of this request
    return responses.send_HTTP_FORBIDDEN("Invalid authentication credentials")
  end

  -- Retrieve consumer
  local consumer = cache.get_or_set(cache.consumer_key(credential.consumer_id), function()
    local result, err = dao.consumers:find_one({ id = credential.consumer_id })
    if err then
      return responses.send_HTTP_INTERNAL_SERVER_ERROR(err)
    end
    return result
  end)

  ngx.req.set_header(constants.HEADERS.CONSUMER_ID, consumer.id)
  ngx.req.set_header(constants.HEADERS.CONSUMER_CUSTOM_ID, consumer.custom_id)
  ngx.req.set_header(constants.HEADERS.CONSUMER_USERNAME, consumer.username)
  ngx.ctx.authenticated_entity = credential
end

return _M
