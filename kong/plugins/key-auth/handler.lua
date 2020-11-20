local constants = require "kong.constants"


local kong = kong
local type = type
local error = error


local KeyAuthHandler = {
  PRIORITY = 1003,
  VERSION = "2.4.0",
}


local EMPTY = {}


local _realm = 'Key realm="' .. _KONG._NAME .. '"'


local function load_credential(key)
  local cred, err = kong.db.keyauth_credentials:select_by_key(key)
  if not cred then
    return nil, err
  end

  return cred, nil, cred.ttl
end


local function set_consumer(consumer, credential)
  kong.client.authenticate(consumer, credential)

  local set_header = kong.service.request.set_header
  local clear_header = kong.service.request.clear_header

  if consumer and consumer.id then
    set_header(constants.HEADERS.CONSUMER_ID, consumer.id)
  else
    clear_header(constants.HEADERS.CONSUMER_ID)
  end

  if consumer and consumer.custom_id then
    set_header(constants.HEADERS.CONSUMER_CUSTOM_ID, consumer.custom_id)
  else
    clear_header(constants.HEADERS.CONSUMER_CUSTOM_ID)
  end

  if consumer and consumer.username then
    set_header(constants.HEADERS.CONSUMER_USERNAME, consumer.username)
  else
    clear_header(constants.HEADERS.CONSUMER_USERNAME)
  end

  if credential and credential.id then
    set_header(constants.HEADERS.CREDENTIAL_IDENTIFIER, credential.id)
  else
    clear_header(constants.HEADERS.CREDENTIAL_IDENTIFIER)
  end

  clear_header(constants.HEADERS.CREDENTIAL_USERNAME)

  if credential then
    clear_header(constants.HEADERS.ANONYMOUS)
  else
    set_header(constants.HEADERS.ANONYMOUS, true)
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


local function do_authentication(conf)
  if type(conf.key_names) ~= "table" then
    kong.log.err("no conf.key_names set, aborting plugin execution")
    return nil, { status = 500, message = "Invalid plugin configuration" }
  end

  local headers = kong.request.get_headers()
  local query = kong.request.get_query()
  local key
  local body

  -- search in headers & querystring
  for i = 1, #conf.key_names do
    local name = conf.key_names[i]
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
        query[name] = nil
        kong.service.request.set_query(query)
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
      return nil, { status = 401, message = "Duplicate API key found" }
    end
  end

  -- this request is missing an API key, HTTP 401
  if not key or key == "" then
    kong.response.set_header("WWW-Authenticate", _realm)
    return nil, { status = 401, message = "No API key found in request" }
  end

  -- retrieve our consumer linked to this API key

  local cache = kong.cache

  local credential_cache_key = kong.db.keyauth_credentials:cache_key(key)
  local credential, err = cache:get(credential_cache_key, nil, load_credential,
                                    key)
  if err then
    return error(err)
  end

  -- no credential in DB, for this key, it is invalid, HTTP 401
  if not credential then
    return nil, { status = 401, message = "Invalid authentication credentials" }
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
    return nil, { status = 500, message = "An unexpected error occurred" }
  end

  set_consumer(consumer, credential)

  return true
end


function KeyAuthHandler:access(conf)
  -- check if preflight request and whether it should be authenticated
  if not conf.run_on_preflight and kong.request.get_method() == "OPTIONS" then
    return
  end

  if conf.anonymous and kong.client.get_credential() then
    -- we're already authenticated, and we're configured for using anonymous,
    -- hence we're in a logical OR between auth methods and we're already done.
    return
  end

  local ok, err = do_authentication(conf)
  if not ok then
    if conf.anonymous then
      -- get anonymous user
      local consumer_cache_key = kong.db.consumers:cache_key(conf.anonymous)
      local consumer, err = kong.cache:get(consumer_cache_key, nil,
                                           kong.client.load_consumer,
                                           conf.anonymous, true)
      if err then
        return error(err)
      end

      set_consumer(consumer)

    else
      return kong.response.error(err.status, err.message, err.headers)
    end
  end
end


return KeyAuthHandler
