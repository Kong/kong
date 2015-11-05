local responses = require "kong.tools.responses"
local utils = require "kong.tools.utils"
local stringy = require "stringy"
local constants = require "kong.constants"

local _M = {}

local GELATO_URL = "^%s/_gelato(/?(\\?[^\\s]*)?)$"

local BASIC_AUTH = "basic-auth"
local KEY_AUTH = "key-auth"
local OAUTH2 = "oauth2"

local RATE_LIMITING = "rate-limiting"
local REQUEST_SIZE_LIMITING = "request-size-limiting"
local RESPONSE_RATE_LIMITING = "response-ratelimiting"

local AUTHENTICATIONS = {
  [KEY_AUTH] = "keyauth_credentials",
  [BASIC_AUTH] = "basicauth_credentials",
  [OAUTH2] = "oauth2_credentials"
}

local function retrieve_parameters()
  ngx.req.read_body()
  -- Parameters could be in both the querystring or body
  return utils.table_merge(ngx.req.get_uri_args(), ngx.req.get_post_args())
end

local function get_authentication(api_id)
  local authentication

  for k, v in pairs(AUTHENTICATIONS) do
    local plugins, err = dao.plugins:find_by_keys({
      api_id = api_id,
      name = k,
      enabled = true
    })
    if err then
      return responses.send_HTTP_INTERNAL_SERVER_ERROR(err)
    end
    if #plugins == 1 and authentication then
      return responses.send_HTTP_INTERNAL_SERVER_ERROR("The API has more than one authentication")
    elseif #plugins == 1 then
      authentication = plugins[1]
    end
  end

  return authentication
end

local function sanitize_credential(authentication, credential)
  if authentication.name == BASIC_AUTH then
    return {
      id = credential.id,
      keys = {
        username = credential.username,
        password = credential.password
      }
    }
  elseif authentication.name == KEY_AUTH then
    return {
      id = credential.id,
      keys = {
        [authentication.config.key_names[1]] = credential.key
      }
    }
  elseif authentication.name == OAUTH2 then
    return {
      id = credential.id,
      keys = {
        client_id = credential.client_id,
        client_secret = credential.client_secret,
        redirect_uri = credential.redirect_uri,
        name = credential.name
      }
    }
  end
  return credential
end

local function find_plugin(name, api_id, consumer_id)
  local plugins, err = dao.plugins:find_by_keys({
    api_id = api_id,
    consumer_id = consumer_id,
    name = name,
    enabled = true
  })
  if err then
    return responses.send_HTTP_INTERNAL_SERVER_ERROR(err)
  end
  if #plugins == 1 then
    return plugins[1] -- Return consumer specific
  else
    local plugins, err = dao.plugins:find_by_keys({
      api_id = api_id,
      name = name,
      consumer_id = constants.DATABASE_NULL_ID,
      enabled = true
    })
    print(#plugins)
    if err then
      return responses.send_HTTP_INTERNAL_SERVER_ERROR(err)
    end
    if #plugins == 1 then
      return plugins[1] -- Return global
    end
  end
end

local function add_notes(authentication, consumer, response)
  local api_id = authentication.api_id
  local consumer_id = consumer.id

  local notes = {}

  -- Rate-Limiting
  local plugin = find_plugin(RATE_LIMITING, api_id, consumer_id)
  if plugin then
    local limits = {}
    for k, v in pairs(plugin.config) do
      table.insert(limits, v.." requests per "..k)
    end
    if #limits > 0 then
      table.insert(notes, {
        description = "Rate Limiting",
        extended = table.concat(limits, ", ")
      })
    end
  end

  -- Request Size Limiting
  plugin = find_plugin(REQUEST_SIZE_LIMITING, api_id, consumer_id)
  if plugin then
    table.insert(notes, {
      description = "Request Size Limiting",
      extended = "Maximum allowed request size is "..plugin.config.allowed_payload_size.."MB"
    })
  end

  -- Response Rate Limiting
  local plugin = find_plugin(RESPONSE_RATE_LIMITING, api_id, consumer_id)
  if plugin then
    local limits = {}
    for k, v in pairs(plugin.config.limits) do
      for l,s in pairs(v) do
        table.insert(limits, s.." requests per "..l.." for "..k)
      end
    end
    if #limits > 0 then
      table.insert(notes, {
        description = "Response Rate Limiting",
        extended = table.concat(limits, ", ")
      })
    end
  end

  response.notes = notes
  return response
end

local function get_consumer(custom_id)
  -- Get consumer
  local consumers, err = dao.consumers:find_by_keys({
    custom_id = custom_id
  })
  if err then
    return responses.send_HTTP_INTERNAL_SERVER_ERROR(err)
  end

  if #consumers == 1 then
    return consumers[1]
  else
    return nil
  end
end

local function create_credential(authentication, params)
  -- Retrieve consumer or create new one
  local consumer_id
  local consumer = get_consumer(params.custom_id)
  if consumer then
    consumer_id = consumer.id
  else
    -- Create consumer
    consumer, err = dao.consumers:insert({
      custom_id = params.custom_id,
    })
    if err then
      return responses.send_HTTP_INTERNAL_SERVER_ERROR(err)
    end
    consumer_id = consumer.id
  end

  local credential_params = {consumer_id = consumer_id}
  if authentication.name == BASIC_AUTH then
    credential_params.username = utils.random_string()
    credential_params.password = utils.random_string()
  elseif authentication.name == OAUTH2 then
    credential_params.redirect_uri = params.redirect_uri
    credential_params.name = params.name
  end

  local credential, err = dao[AUTHENTICATIONS[authentication.name]]:insert(utils.deep_copy(credential_params))
  if err then
    return responses.send_HTTP_BAD_REQUEST(tostring(err))
  end

  credential_params.id = credential.id
  local result = {
    authentication_name = authentication.name,
    credential = sanitize_credential(authentication, authentication.name == BASIC_AUTH and credential_params or credential)
  }

  return responses.send_HTTP_OK(add_notes(authentication, consumer, result))
end

local function retrieve_credentials(authentication, custom_id)
  -- Get consumer
  local consumer = get_consumer(custom_id)
  if not consumer then
    return responses.send_HTTP_NOT_FOUND("Consumer not found")
  end

  local credentials, err = dao[AUTHENTICATIONS[authentication.name]]:find_by_keys({
    consumer_id = consumer.id
  })
  if err then
    return responses.send_HTTP_INTERNAL_SERVER_ERROR(err)
  end

  local result = {}
  for _, v in ipairs(credentials) do
    if not result.credentials then result.credentials = {} end
    table.insert(result.credentials, sanitize_credential(authentication, v))
  end

  result.authentication_name = authentication.name
  return responses.send_HTTP_OK(add_notes(authentication, consumer, result))
end

local function delete_credential(authentication, custom_id, credential_id)
  local consumer = get_consumer(custom_id)
  if not consumer then
    return responses.send_HTTP_NOT_FOUND("Consumer not found")
  end

  local ok, err = dao[AUTHENTICATIONS[authentication.name]]:delete({
    consumer_id = consumer.id,
    id = credential_id
  })
  if ok then
    return responses.send_HTTP_OK()
  end
  
  responses.send_HTTP_NOT_FOUND("Credential not found")
end

local function get_secret(authorization_header)
  local secret
  if authorization_header then
    secret = stringy.split(ngx.decode_base64(authorization_header), ":")[1]
  end
  return secret
end

function _M.execute(conf)
  -- Check if the API has a request_path and if it's being invoked with the path resolver
  local path_prefix = (ngx.ctx.api.request_path and stringy.startswith(ngx.var.request_uri, ngx.ctx.api.request_path)) and ngx.ctx.api.request_path or ""
  if stringy.endswith(path_prefix, "/") then
    path_prefix = path_prefix:sub(1, path_prefix:len() - 1)
  end

  if ngx.re.match(ngx.var.request_uri, string.format(GELATO_URL, path_prefix)) then
    -- Verify secret
    local secret = get_secret(ngx.req.get_headers()["authorization"])
    if conf.secret ~= secret then
      return responses.send_HTTP_FORBIDDEN("Invalid \"secret\"")
    end

    -- Verify that the API has a valid authentication
    local authentication = get_authentication(ngx.ctx.api.id)
    if not authentication then
      return responses.send_HTTP_BAD_REQUEST("The API either has not authentication, or has an unsupported authentication")
    else
      local params = retrieve_parameters()
      if not params.custom_id or stringy.strip(params.custom_id) == "" then
        return responses.send_HTTP_BAD_REQUEST("Missing \"custom_id\"")
      end

      local method = ngx.req.get_method()
      if method == "POST" then
        create_credential(authentication, params)
      elseif method == "GET" then
        retrieve_credentials(authentication, params.custom_id)
      elseif method == "DELETE" then
        delete_credential(authentication, params.custom_id, params.credential_id)
      else
        response.send_HTTP_METHOD_NOT_ALLOWED()
      end
    end
  end
end

return _M
