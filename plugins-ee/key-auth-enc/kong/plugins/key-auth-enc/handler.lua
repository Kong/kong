-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local constants = require "kong.constants"
local meta = require "kong.meta"
local workspaces = require "kong.workspaces"


local kong = kong
local type = type


local _realm = 'Key realm="' .. _KONG._NAME .. '"'


local KeyAuthHandler = {}


KeyAuthHandler.PRIORITY = 1250
KeyAuthHandler.VERSION = meta.core_version


local function load_credential_ids(key)
  return kong.db.keyauth_enc_credentials:select_ids_by_ident(key)
end


local function load_credential(id)
  local cred, err = kong.db.keyauth_enc_credentials:select({ id = id })
  if not cred then
    return nil, err
  end
  if cred.ttl == 0 then
    kong.log.debug("key expired")

    return nil
  end

  return cred, nil, cred.ttl
end


local function get_credential_ids(key, sha1_fallback)
  local cache = kong.cache
  local credential_cache_key, err = kong.db.keyauth_enc_credentials:key_ident_cache_key(
    { key = key },
    sha1_fallback
  )
  if not credential_cache_key then
    return nil, err
  end
  local credential_ids = cache:get(credential_cache_key, { resurrect_ttl = 0.001 },
                                   load_credential_ids, key)
  return credential_ids
end


local function get_keyauth_credential(key)
  local cache = kong.cache
  local credential_ids, err = get_credential_ids(key)
  if err then
    return nil, err
  end

  if not credential_ids or #credential_ids == 0 then
    -- check credentials with sha1 identifier
    credential_ids, err = get_credential_ids(key, true)
    if err then
      return nil, err
    end
  end

  --return keyauth_enc_credentials:validate_ident(credential_ids, key)

  for _, id in ipairs(credential_ids) do
    local c = kong.db.keyauth_enc_credentials:cache_key({ id = id.id })
    local cred, err, hit_level = cache:get(c, { resurrect_ttl = 0.001 }, load_credential, id.id)
    if err then
      return nil, err
    end
    kong.log.debug("cache hit level: ", hit_level)

    if cred and cred.key == key then
      return cred
    end
  end
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
      set_header(constants.HEADERS.CREDENTIAL_IDENTIFIER, credential.username)
    else
      clear_header(constants.HEADERS.CREDENTIAL_IDENTIFIER)
    end

    clear_header(constants.HEADERS.ANONYMOUS)

  else
    clear_header(constants.HEADERS.CREDENTIAL_IDENTIFIER)
    set_header(constants.HEADERS.ANONYMOUS, true)
  end
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

  -- EE: FT-891
  local key_in_body = conf.key_in_body

  -- read in the body if we want to examine POST args
  if key_in_body then
    local err
    body, err = kong.request.get_body()

    if err then
      kong.log.err("Cannot process request body: ", err)
      -- EE: FT-891
      -- return nil, { status = 400, message = "Cannot process request body" }
      key_in_body =  false
    end
  end

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
    if not v and key_in_body then
      v = body[name]
    end

    if type(v) == "string" then
      key = v

      if conf.hide_credentials then
        query[name] = nil
        kong.service.request.set_query(query)
        kong.service.request.clear_header(name)

        if key_in_body then
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
  if not key or key == "" then
    kong.response.set_header("WWW-Authenticate", _realm)
    return nil, { status = 401, message = "No API key found in request" }
  end

  -- retrieve our consumer linked to this API key

  local credential, err = get_keyauth_credential(key)

  if err then
    kong.log.err(err)
    return kong.response.exit(500, "An unexpected error occurred")
  end

  -- no credential in DB, for this key, it is invalid, HTTP 401
  if not credential then
    return nil, { status = 401, message = "Unauthorized" }
  end

  -----------------------------------------
  -- Success, this request is authenticated
  -----------------------------------------

  -- retrieve the consumer linked to this API key, to set appropriate headers
  local cache = kong.cache
  local consumer_cache_key, consumer
  consumer_cache_key = kong.db.consumers:cache_key(credential.consumer.id)
  consumer, err      = cache:get(consumer_cache_key, nil, kong.client.load_consumer,
                                 credential.consumer.id)
  if err then
    kong.log.err(err)
    return nil, { status = 500, message = "An unexpected error occurred" }
  end

  set_consumer(consumer, credential)

  return true
end


local function invalidate_key(entity, sha1_fallback)
  local cache_key, err = kong.db.keyauth_enc_credentials:key_ident_cache_key(
    entity,
    sha1_fallback
  )

  if cache_key then
    kong.cache:invalidate(cache_key)
  elseif err then
    kong.log.warn(err)
  end
end


function KeyAuthHandler:init_worker()
  if kong.configuration.database == "off" or not (kong.worker_events and kong.worker_events.register) then
    return
  end

  kong.worker_events.register(function(data)
    workspaces.set_workspace(data.workspace)

    invalidate_key(data.entity)
    -- invalidate any cached credentials with sha1 identifier
    invalidate_key(data.entity, true)

    if data.old_entity and data.old_entity.key then
      invalidate_key(data.old_entity)
      invalidate_key(data.old_entity, true)
    end
  end, "crud", "keyauth_enc_credentials")
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
                                           kong.client.load_consumer, conf.anonymous, true)
      if err then
        kong.log.err("failed to load anonymous consumer:", err)
        return kong.response.exit(500, { message = "An unexpected error occurred" })
      end

      set_consumer(consumer, nil)

    else
      return kong.response.exit(err.status, { message = err.message }, err.headers)
    end
  end
end

KeyAuthHandler.ws_handshake = KeyAuthHandler.access

return KeyAuthHandler
