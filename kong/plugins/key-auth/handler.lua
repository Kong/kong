local constants = require "kong.constants"
local kong_meta = require "kong.meta"


local kong = kong
local type = type
local error = error
local ipairs = ipairs
local tostring = tostring
local fmt = string.format


local HEADERS_CONSUMER_ID           = constants.HEADERS.CONSUMER_ID
local HEADERS_CONSUMER_CUSTOM_ID    = constants.HEADERS.CONSUMER_CUSTOM_ID
local HEADERS_CONSUMER_USERNAME     = constants.HEADERS.CONSUMER_USERNAME
local HEADERS_CREDENTIAL_IDENTIFIER = constants.HEADERS.CREDENTIAL_IDENTIFIER
local HEADERS_ANONYMOUS             = constants.HEADERS.ANONYMOUS


local KeyAuthHandler = {
  VERSION = kong_meta.version,
  PRIORITY = 1250,
}


local EMPTY = {}


local ERR_DUPLICATE_API_KEY   = "Duplicate API key found"
local ERR_NO_API_KEY          = "No API key found in request"
local ERR_INVALID_AUTH_CRED   = "Unauthorized"
local ERR_INVALID_PLUGIN_CONF = "Invalid plugin configuration"
local ERR_UNEXPECTED          = "An unexpected error occurred"


local function load_credential(key)
  local cred, err = kong.db.keyauth_credentials:select_by_key(key)
  if not cred then
    return nil, err
  end

  if cred.ttl == 0 then
    kong.log.debug("key expired")

    return nil
  end

  return cred, nil, cred.ttl
end


local function set_consumer(consumer, credential)
  kong.client.authenticate(consumer, credential)

  local set_header = kong.service.request.set_header
  local clear_header = kong.service.request.clear_header

  if consumer and consumer.id then
    set_header(HEADERS_CONSUMER_ID, consumer.id)
  else
    clear_header(HEADERS_CONSUMER_ID)
  end

  if consumer and consumer.custom_id then
    set_header(HEADERS_CONSUMER_CUSTOM_ID, consumer.custom_id)
  else
    clear_header(HEADERS_CONSUMER_CUSTOM_ID)
  end

  if consumer and consumer.username then
    set_header(HEADERS_CONSUMER_USERNAME, consumer.username)
  else
    clear_header(HEADERS_CONSUMER_USERNAME)
  end

  if credential and credential.id then
    set_header(HEADERS_CREDENTIAL_IDENTIFIER, credential.id)
  else
    clear_header(HEADERS_CREDENTIAL_IDENTIFIER)
  end

  if credential then
    clear_header(HEADERS_ANONYMOUS)
  else
    set_header(HEADERS_ANONYMOUS, true)
  end
end


local function get_body()
  local body, err = kong.request.get_body()
  if err then
    kong.log.info("Cannot process request body: ", err)
    return EMPTY
  end

  return body
end

local function server_error(message)
  return { status = 500, message = message }
end

local function unauthorized(message, www_auth_content)
  return { status = 401, message = message, headers = { ["WWW-Authenticate"] = www_auth_content } }
end

local function do_authentication(conf)
  if type(conf.key_names) ~= "table" then
    kong.log.err("no conf.key_names set, aborting plugin execution")
    return nil, server_error(ERR_INVALID_PLUGIN_CONF)
  end

  local www_auth_content = conf.realm and fmt('Key realm="%s"', conf.realm) or 'Key'
  local headers = kong.request.get_headers()
  local query = kong.request.get_query()
  local key
  local body

  -- search in headers & querystring
  for _, name in ipairs(conf.key_names) do
    local v

    if conf.key_in_header then
      v = headers[name]
    end

    if not v and conf.key_in_query then
      -- search in querystring
      v = query[name]
    end

    -- search the body, if we asked to
    if not v and conf.key_in_body then
      if not body then
        body = get_body()
      end

      v = body[name]
    end

    if type(v) == "string" then
      key = v

      if conf.hide_credentials then
        kong.service.request.clear_query_arg(name)
        kong.service.request.clear_header(name)

        if conf.key_in_body then
          if not body then
            body = get_body()
          end

          if body ~= EMPTY then
            if body then
              body[name] = nil
            end

            kong.service.request.set_body(body)
          end
        end
      end

      break

    elseif type(v) == "table" then
      -- duplicate API key
      return nil, unauthorized(ERR_DUPLICATE_API_KEY, www_auth_content)
    end
  end

  -- this request is missing an API key, HTTP 401
  if not key or key == "" then
    return nil, unauthorized(ERR_NO_API_KEY, www_auth_content)
  end

  -- retrieve our consumer linked to this API key

  local cache = kong.cache

  local credential_cache_key = kong.db.keyauth_credentials:cache_key(key)
  -- hit_level be 1 if stale value is propelled into L1 cache; so set a minimal `resurrect_ttl`
  local credential, err, hit_level = cache:get(credential_cache_key, { resurrect_ttl = 0.001 }, load_credential,
                                    key)

  if err then
    return error(err)
  end

  kong.log.debug("credential hit_level: ", tostring(hit_level))

  -- no credential in DB, for this key, it is invalid, HTTP 401
  if not credential or hit_level == 4 then
    return nil, unauthorized(ERR_INVALID_AUTH_CRED, www_auth_content)
  end

  -----------------------------------------
  -- Success, this request is authenticated
  -----------------------------------------

  -- retrieve the consumer linked to this API key, to set appropriate headers
  local consumer_cache_key, consumer
  consumer_cache_key = kong.db.consumers:cache_key(credential.consumer.id)
  consumer, err      = cache:get(consumer_cache_key, nil,
                                 kong.client.load_consumer,
                                 credential.consumer.id)
  if err then
    kong.log.err(err)
    return nil, server_error(ERR_UNEXPECTED)
  end

  set_consumer(consumer, credential)

  return true
end

local function set_anonymous_consumer(anonymous)
  local consumer_cache_key = kong.db.consumers:cache_key(anonymous)
  local consumer, err = kong.cache:get(consumer_cache_key, nil,
                                        kong.client.load_consumer,
                                        anonymous, true)
  if err then
    return error(err)
  end

  set_consumer(consumer)
end


--- When conf.anonymous is enabled we are in "logical OR" authentication flow.
--- Meaning - either anonymous consumer is enabled or there are multiple auth plugins
--- and we need to passthrough on failed authentication.
local function logical_OR_authentication(conf)
  if kong.client.get_credential() then
    -- we're already authenticated and in "logical OR" between auth methods -- early exit
    return
  end

  local ok, _ = do_authentication(conf)
  if not ok then
    set_anonymous_consumer(conf.anonymous)
  end
end

--- When conf.anonymous is not set we are in "logical AND" authentication flow.
--- Meaning - if this authentication fails the request should not be authorized
--- even though other auth plugins might have successfully authorized user.
local function logical_AND_authentication(conf)
  local ok, err = do_authentication(conf)
  if not ok then
    return kong.response.error(err.status, err.message, err.headers)
  end
end


function KeyAuthHandler:access(conf)
  -- check if preflight request and whether it should be authenticated
  if not conf.run_on_preflight and kong.request.get_method() == "OPTIONS" then
    return
  end

  if conf.anonymous then
    return logical_OR_authentication(conf)
  else
    return logical_AND_authentication(conf)
  end
end


return KeyAuthHandler
