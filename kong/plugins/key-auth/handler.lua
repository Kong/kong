local constants = require "kong.constants"
local BasePlugin = require "kong.plugins.base_plugin"

local type = type

local _realm = 'Key realm="' .. _KONG._NAME .. '"'

local KeyAuthHandler = BasePlugin:extend()

KeyAuthHandler.PRIORITY = 1003
KeyAuthHandler.VERSION = "0.2.0"


function KeyAuthHandler:new()
  KeyAuthHandler.super.new(self, "key-auth")
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
  local const = constants.HEADERS

  local new_headers = {
    [const.CONSUMER_ID]        = consumer.id,
    [const.CONSUMER_CUSTOM_ID] = tostring(consumer.custom_id),
    [const.CONSUMER_USERNAME]  = consumer.username,
  }

  kong.ctx.shared.authenticated_consumer = consumer -- forward compatibility
  ngx.ctx.authenticated_consumer = consumer         -- backward compatibility

  if credential then
    kong.ctx.shared.authenticated_credential = credential -- forward compatibility
    ngx.ctx.authenticated_credential = credential         -- backward compatibility
    new_headers[const.CREDENTIAL_USERNAME] = credential.username
    kong.service.request.clear_header(const.ANONYMOUS) -- in case of auth plugins concatenation

  else
    new_headers[const.ANONYMOUS] = true
  end

  kong.service.request.set_headers(new_headers)
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

  -- read in the body if we want to examine POST args
  if conf.key_in_body then
    local err
    body, err = kong.request.get_body()

    if err then
      kong.log.err("Cannot process request body: ", err)
      return nil, { status = 400, message = "Cannot process request body" }
    end
  end

  -- search in headers & querystring
  for i = 1, #conf.key_names do
    local name = conf.key_names[i]
    local v = headers[name]
    if not v then
      -- search in querystring
      v = query[name]
    end

    -- search the body, if we asked to
    if not v and conf.key_in_body then
      v = body[name]
    end

    if type(v) == "string" then
      key = v

      if conf.hide_credentials then
        query[name] = nil
        kong.service.request.set_query(query)
        kong.service.request.clear_header(name)

        if conf.key_in_body then
          body[name] = nil
          kong.service.request.set_body(body)
        end
      end

      break

    elseif type(v) == "table" then
      -- duplicate API key
      return nil, { status = 401, message = "Duplicate API key found" }
    end
  end

  -- this request is missing an API key, HTTP 401
  if not key then
    kong.response.set_header("WWW-Authenticate", _realm)
    return nil, { status = 401, message = "No API key found in request" }
  end

  -- retrieve our consumer linked to this API key

  local cache = kong.cache

  local credential_cache_key = kong.db.keyauth_credentials:cache_key(key)
  local credential, err = cache:get(credential_cache_key, nil, load_credential,
                                    key)
  if err then
    kong.log.err(err)
    return kong.response.exit(500, "An unexpected error ocurred")
  end

  -- no credential in DB, for this key, it is invalid, HTTP 403
  if not credential then
    return nil, { status = 403, message = "Invalid authentication credentials" }
  end

  -----------------------------------------
  -- Success, this request is authenticated
  -----------------------------------------

  -- retrieve the consumer linked to this API key, to set appropriate headers

  local consumer_cache_key = kong.db.consumers:cache_key(credential.consumer.id)
  local consumer, err      = cache:get(consumer_cache_key, nil, load_consumer,
                                       credential.consumer.id)
  if err then
    kong.log.err(err)
    return nil, { status = 500, message = "An unexpected error ocurred" }
  end

  set_consumer(consumer, credential)

  return true
end


function KeyAuthHandler:access(conf)
  KeyAuthHandler.super.access(self)

  -- check if preflight request and whether it should be authenticated
  if not conf.run_on_preflight and kong.request.get_method() == "OPTIONS" then
    return
  end

  -- checking both old and new ctx for backward and forward compatibility
  local authenticated_credential = kong.ctx.shared.authenticated_credential
                                   or ngx.ctx.authenticated_credential
  if authenticated_credential and conf.anonymous ~= "" then
    -- we're already authenticated, and we're configured for using anonymous,
    -- hence we're in a logical OR between auth methods and we're already done.
    return
  end

  local ok, err = do_authentication(conf)
  if not ok then
    if conf.anonymous ~= "" then
      -- get anonymous user
      local consumer_cache_key = kong.db.consumers:cache_key(conf.anonymous)
      local consumer, err = kong.cache:get(consumer_cache_key, nil,
                                           load_consumer, conf.anonymous, true)
      if err then
        kong.log.err(err)
        return kong.response.exit(500, { message = "An unexpected error ocurred" })
      end

      set_consumer(consumer, nil)

    else
      return kong.response.exit(err.status, { message = err.message }, err.headers)
    end
  end
end


return KeyAuthHandler
