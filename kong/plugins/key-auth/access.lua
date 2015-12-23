local cache = require "kong.tools.database_cache"
local responses = require "kong.tools.responses"
local constants = require "kong.constants"

local _M = {}

-- Fast lookup for credential retrieval depending on the type of the authentication
--
-- All methods must respect:
--
-- @param request ngx request object
-- @param {table} conf Plugin config
-- @return {string} public_key
-- @return {string} private_key
local retrieve_credentials = {
  [constants.AUTHENTICATION.HEADER] = function(request, conf)
    local key
    local headers = request.get_headers()

    if conf.key_names then
      for _, key_name in ipairs(conf.key_names) do
        if headers[key_name] ~= nil then
          key = headers[key_name]

          if conf.hide_credentials then
            request.clear_header(key_name)
          end

          return key
        end
      end
    end
  end,
  [constants.AUTHENTICATION.QUERY] = function(request, conf)
    if conf.key_names then
      local key
      local uri_params = request.get_uri_args()
      for _, key_name in ipairs(conf.key_names) do
        key = uri_params[key_name]
        if key ~= nil then
          if conf.hide_credentials then
            uri_params[key_name] = nil
            request.set_uri_args(uri_params)
          end
          return key
        end
      end
    end
  end
}

function _M.execute(conf)
  local key, key_found, credential
  for _, v in ipairs({ constants.AUTHENTICATION.QUERY, constants.AUTHENTICATION.HEADER }) do
    key = retrieve_credentials[v](ngx.req, conf)
    if key then
      key_found = true
      credential = cache.get_or_set(cache.keyauth_credential_key(key), function()
        local credentials, err = dao.keyauth_credentials:find_by_keys {key = key}
        local result
        if err then
          return responses.send_HTTP_INTERNAL_SERVER_ERROR(err)
        elseif #credentials > 0 then
          result = credentials[1]
        end
        return result
      end)
      if credential then break end
    end
  end

  -- No key found in the request's headers or parameters
  if not key_found then
    ngx.header["WWW-Authenticate"] = "Key realm=\""..constants.NAME.."\""
    return responses.send_HTTP_UNAUTHORIZED("No API Key found in headers, body or querystring")
  end

  -- No key found in the DB, this credential is invalid
  if not credential then
    return responses.send_HTTP_FORBIDDEN("Invalid authentication credentials")
  end

  -- Retrieve consumer
  local consumer = cache.get_or_set(cache.consumer_key(credential.consumer_id), function()
    local result, err = dao.consumers:find_by_primary_key({id = credential.consumer_id})
    if err then
      return responses.send_HTTP_INTERNAL_SERVER_ERROR(err)
    end
    return result
  end)

  ngx.req.set_header(constants.HEADERS.CONSUMER_ID, consumer.id)
  ngx.req.set_header(constants.HEADERS.CONSUMER_CUSTOM_ID, consumer.custom_id)
  ngx.req.set_header(constants.HEADERS.CONSUMER_USERNAME, consumer.username)
  ngx.ctx.authenticated_credential = credential
end

return _M
