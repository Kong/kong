local cache = require "kong.tools.database_cache"
local responses = require "kong.tools.responses"
local constants = require "kong.constants"
local singletons = require "kong.singletons"
local BasePlugin = require "kong.plugins.base_plugin"

local set_header = ngx.req.set_header
local get_headers = ngx.req.get_headers
local set_uri_args = ngx.req.set_uri_args
local get_uri_args = ngx.req.get_uri_args
local clear_header = ngx.req.clear_header
local type = type

local _realm = 'Key realm="'.._KONG._NAME..'"'

local KeyAuthHandler = BasePlugin:extend()

KeyAuthHandler.PRIORITY = 1000

local get_method = ngx.req.get_method

function KeyAuthHandler:new()
  KeyAuthHandler.super.new(self, "key-auth")
end

function KeyAuthHandler:access(conf)
  KeyAuthHandler.super.access(self)

  -- check if preflight request and should be authenticated
  if not conf.authenticate_preflight and get_method() == "OPTIONS" then
    return
  end

  if type(conf.key_names) ~= "table" then
    ngx.log(ngx.ERR, "[key-auth] no conf.key_names set, aborting plugin execution")
    return
  end

  local key
  local headers = get_headers()
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
      return responses.send_HTTP_UNAUTHORIZED("Duplicate API key found")
    end
  end

  -- this request is missing an API key, HTTP 401
  if not key then
    ngx.header["WWW-Authenticate"] = _realm
    return responses.send_HTTP_UNAUTHORIZED("No API key found in headers"
                                          .." or querystring")
  end

  -- retrieve our consumer linked to this API key
  local credential = cache.get_or_set(cache.keyauth_credential_key(key), function()
    local creds, err = singletons.dao.keyauth_credentials:find_all {
      key = key
    }
    if not creds then
      return responses.send_HTTP_INTERNAL_SERVER_ERROR(err)
    elseif #creds > 0 then
      return creds[1]
    end
  end)

  -- no credential in DB, for this key, it is invalid, HTTP 403
  if not credential then
    return responses.send_HTTP_FORBIDDEN("Invalid authentication credentials")
  end

  -----------------------------------------
  -- Success, this request is authenticated
  -----------------------------------------

  -- retrieve the consumer linked to this API key, to set appropriate headers
  local consumer = cache.get_or_set(cache.consumer_key(credential.consumer_id), function()
    local row, err = singletons.dao.consumers:find {
      id = credential.consumer_id
    }
    if not row then
      return responses.send_HTTP_INTERNAL_SERVER_ERROR(err)
    end
    return row
  end)

  set_header(constants.HEADERS.CONSUMER_ID, consumer.id)
  set_header(constants.HEADERS.CONSUMER_CUSTOM_ID, consumer.custom_id)
  set_header(constants.HEADERS.CONSUMER_USERNAME, consumer.username)
  ngx.ctx.authenticated_credential = credential
  ngx.ctx.authenticated_consumer = consumer
end

return KeyAuthHandler
