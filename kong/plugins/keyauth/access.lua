local cache = require "kong.tools.database_cache"
local stringy = require "stringy"
local Multipart = require "multipart"
local responses = require "kong.tools.responses"
local constants = require "kong.constants"

local CONTENT_TYPE = "content-type"
local CONTENT_LENGTH = "content-length"
local FORM_URLENCODED = "application/x-www-form-urlencoded"
local MULTIPART_DATA = "multipart/form-data"

local _M = {}

local function skip_authentication(headers)
  -- Skip upload request that expect a 100 Continue response
  return headers["expect"] and stringy.startswith(headers["expect"], "100")
end

local function get_key_from_query(key_name, request, conf)
  local key, parameters
  local found_in = {}

  -- First, try with querystring
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
    local key

    if conf.key_names then
      for _, key_name in ipairs(conf.key_names) do
        key = get_key_from_query(key_name, request, conf)

        if key then
          return key
        end
      end
    end
  end
}

function _M.execute(conf)
  if not conf or skip_authentication(ngx.req.get_headers()) then return end

  local credential
  for _, v in ipairs({ constants.AUTHENTICATION.QUERY, constants.AUTHENTICATION.HEADER }) do
    local key = retrieve_credentials[v](ngx.req, conf)

    -- Make sure we are not sending an empty table to find_by_keys
    if key then
      credential = cache.get_or_set(cache.keyauth_credential_key(key), function()
        local credentials, err = dao.keyauth_credentials:find_by_keys { key = key }
        local result
        if err then
          return responses.send_HTTP_INTERNAL_SERVER_ERROR(err)
        elseif #credentials > 0 then
          result = credentials[1]
        end
        return result
      end)
    end

    if credential then break end
  end

  if not credential then
    ngx.ctx.stop_phases = true -- interrupt other phases of this request
    return responses.send_HTTP_FORBIDDEN("Invalid authentication credentials")
  end

  -- Retrieve consumer
  local consumer = cache.get_or_set(cache.consumer_key(credential.consumer_id), function()
    local result, err = dao.consumers:find_by_primary_key({ id = credential.consumer_id })
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
