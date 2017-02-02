local cache = require "kong.tools.database_cache"
local responses = require "kong.tools.responses"
local constants = require "kong.constants"
local singletons = require "kong.singletons"
local BasePlugin = require "kong.plugins.base_plugin"

local ngx_set_header = ngx.req.set_header
local ngx_get_headers = ngx.req.get_headers
local set_uri_args = ngx.req.set_uri_args
local get_uri_args = ngx.req.get_uri_args
local clear_header = ngx.req.clear_header
local type = type

local _realm = 'Key realm="'.._KONG._NAME..'"'

local KeyAuthHandler = BasePlugin:extend()

KeyAuthHandler.PRIORITY = 1000

function KeyAuthHandler:new()
  KeyAuthHandler.super.new(self, "key-auth")
end

local function load_credential(key)
  local creds, err = singletons.dao.keyauth_credentials:find_all {
    key = key
  }
  if not creds then
    return responses.send_HTTP_INTERNAL_SERVER_ERROR(err)
  end
  return creds[1]
end

local function load_consumer(consumer_id, anonymous)
  local result, err = singletons.dao.consumers:find { id = consumer_id }
  if not result then
    if anonymous and not err then
      err = 'anonymous consumer "'..consumer_id..'" not found'
    end
    return responses.send_HTTP_INTERNAL_SERVER_ERROR(err)
  end
  return result
end

local function set_consumer(consumer, credential)
  ngx_set_header(constants.HEADERS.CONSUMER_ID, consumer.id)
  ngx_set_header(constants.HEADERS.CONSUMER_CUSTOM_ID, consumer.custom_id)
  ngx_set_header(constants.HEADERS.CONSUMER_USERNAME, consumer.username)
  ngx.ctx.authenticated_consumer = consumer
  if credential then
    ngx_set_header(constants.HEADERS.CREDENTIAL_USERNAME, credential.username)
    ngx.ctx.authenticated_credential = credential
    ngx_set_header(constants.HEADERS.ANONYMOUS, nil) -- in case of auth plugins concatenation
  else
    ngx_set_header(constants.HEADERS.ANONYMOUS, true)
  end
  
end

local function do_authentication(conf)
  if type(conf.key_names) ~= "table" then
    ngx.log(ngx.ERR, "[key-auth] no conf.key_names set, aborting plugin execution")
    return false, {status = 500, message= "Invalid plugin configuration"}
  end

  local key
  local headers = ngx_get_headers()
  local uri_args = get_uri_args()

  -- search in headers & querystring
  for i = 1, #conf.key_names do
    local name = conf.key_names[i]
    local v = headers[name]
    if not v then
      -- search in querystring
      v = uri_args[name]
    end

    if type(v) == "string" then
      key = v
      if conf.hide_credentials then
        uri_args[name] = nil
        set_uri_args(uri_args)
        clear_header(name)
      end
      break
    elseif type(v) == "table" then
      -- duplicate API key, HTTP 401
      return false, {status = 401, message = "Duplicate API key found"}
    end
  end

  -- this request is missing an API key, HTTP 401
  if not key then
    ngx.header["WWW-Authenticate"] = _realm
    return false, {status = 401, message = "No API key found in headers"
                                          .." or querystring"}
  end

  -- retrieve our consumer linked to this API key
  local credential = cache.get_or_set(cache.keyauth_credential_key(key),
                                      nil, load_credential, key)

  -- no credential in DB, for this key, it is invalid, HTTP 403
  if not credential then
    return false, {status = 403, message = "Invalid authentication credentials"}
  end

  -----------------------------------------
  -- Success, this request is authenticated
  -----------------------------------------

  -- retrieve the consumer linked to this API key, to set appropriate headers
  local consumer = cache.get_or_set(cache.consumer_key(credential.consumer_id),
                                    nil, load_consumer, credential.consumer_id)

  set_consumer(consumer, credential)

  return true
end

function KeyAuthHandler:access(conf)
  KeyAuthHandler.super.access(self)

  local ok, err = do_authentication(conf)
  if not ok then
    if conf.anonymous ~= "" then
      -- get anonymous user
      local consumer = cache.get_or_set(cache.consumer_key(conf.anonymous),
                       nil, load_consumer, conf.anonymous, true)
      set_consumer(consumer, nil)
    else
      return responses.send(err.status, err.message, err.headers)
    end
  end
end

return KeyAuthHandler
