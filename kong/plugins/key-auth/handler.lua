local constants = require "kong.constants"
local sha256 = require "resty.sha256"
local to_hex = require "resty.string".to_hex


local kong = kong
local type = type


local _realm = 'Key realm="' .. _KONG._NAME .. '"'


local KeyAuthHandler = {}


KeyAuthHandler.PRIORITY = 1003
KeyAuthHandler.VERSION = "2.1.0"


local function check_parameters (table_of_parameter_names, search_in_body, hide_credentials, headers, query, body)
  -- search parameter in headers & querystring
  local parameter = ""
  for i = 1, #table_of_parameter_names do
    local name = table_of_parameter_names[i]
    local v = headers[name]
    if not v then
      -- search in querystring
      v = query[name]
    end

    -- search the body, if we asked to
    if not v and search_in_body then
      v = body[name]
    end

    if type(v) == "string" then
      parameter = v

      if hide_credentials then
        query[name] = nil
        kong.service.request.set_query(query)
        kong.service.request.clear_header(name)

        if search_in_body then
          body[name] = nil
          kong.service.request.set_body(body)
        end
      end

      break

    elseif type(v) == "table" then
      -- duplicate parameter
      return nil, { status = 401, message = "Duplicate " .. title_of_parameter .. " found" }
    end
  end
  return parameter
end


local function load_credential(key)
  local cred, err = kong.db.keyauth_credentials:select_by_key(key)
  if not cred then
    return nil, err
  end
  return cred
end


local function load_consumer(consumer_id, anonymous)
  local result, err = kong.db.consumers:select({ id = consumer_id })
  if not result then
    if anonymous and not err then
      err = 'anonymous consumer "' .. consumer_id .. '" not found'
    end

    return nil, err
  end

  return result
end


local function set_consumer(consumer, credential)
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

  kong.client.authenticate(consumer, credential)

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
  local headers = kong.request.get_headers()
  local query = kong.request.get_query()
  local key
  local signature
  local body

  -- read in the body if we want to examine POST args
  if conf.key_in_body or conf.signature_in_body then
    local err
    body, err = kong.request.get_body()

    if err then
      kong.log.err("Cannot process request body: ", err)
      return nil, { status = 400, message = "Cannot process request body" }
    end
  end

  -- search for api key in headers & querystring (and maybe body)
  key = check_parameters (conf.key_names, conf.key_in_body, conf.hide_credentials, headers, query, body)
  if not key or key == "" then
    kong.response.set_header("WWW-Authenticate", _realm)
    return nil, { status = 401, message = "No api key found in request" }
  end
  
  if conf.verify_signature then
    -- search for signature in headers & querystring (and maybe body)
    signature = check_parameters (conf.signature_names, conf.signature_in_body, conf.hide_credentials, headers, query, body)
    if not signature or signature == "" then
      kong.response.set_header("WWW-Authenticate", _realm)
      return nil, { status = 401, message = "No signature found in request" }
    end
  end

  local cache = kong.cache

  local credential_cache_key = kong.db.keyauth_credentials:cache_key(key)
  local credential, err = cache:get(credential_cache_key, nil, load_credential, key)
  if err then
    kong.log.err(err)
    return kong.response.exit(500, {
      message = "An unexpected error occurred"
    })
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
  consumer, err      = cache:get(consumer_cache_key, nil, load_consumer, credential.consumer.id)
  if err then
    kong.log.err(err)
    return nil, { status = 500, message = "An unexpected error occurred" }
  end

  if conf.verify_signature then
    -- 4. Verify sha256
    local secret = credential.secret
    local now = ngx.time()
    local sha = sha256:new()
    local ks = key .. secret


    local verify_sig = function(time)
      sha:reset()
      sha:update(ks)
      sha:update(tostring(time))
      local final = to_hex(sha:final())
      return signature == final
    end

    if verify_sig(now) then
      set_consumer(consumer, credential)
      return true
    end

    for distance = 1, conf.signature_distance_seconds do
      if verify_sig(now + distance) or verify_sig(now - distance) then

        -- authenticated with `distance` seconds
        set_consumer(consumer, credential)
        return true
      end
    end

    return nil, { status = 401, message = "Invalid signature" }
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
                                           load_consumer, conf.anonymous, true)
      if err then
        kong.log.err(err)
        return kong.response.exit(500, { message = "An unexpected error occurred" })
      end

      set_consumer(consumer, nil)

    else
      return kong.response.exit(err.status, { message = err.message }, err.headers)
    end
  end
end


return KeyAuthHandler
