-- Copyright (C) Kong Inc.

local BasePlugin = require "kong.plugins.base_plugin"
local constants = require "kong.constants"

local utils = require "kong.tools.utils"
local Multipart = require "multipart"
local cjson = require "cjson.safe"
local http = require "resty.http"
local url = require "socket.url"

local OAuth2Introspection = BasePlugin:extend()

local CONTENT_TYPE = "content-type"
local CONTENT_LENGTH = "content-length"
local ACCESS_TOKEN = "access_token"

local kong = kong
local req_get_headers = ngx.req.get_headers
local ngx_set_header = ngx.req.set_header
local get_method = ngx.req.get_method
local string_find = string.find
local table_insert = table.insert
local fmt = string.format
local ngx_log = ngx.log
local ERR = ngx.ERR
local WARN = ngx.WARN

local consumer_by_fields = {
  "username",
  "client_id",
}

local CONSUMER_BY_DEFAULT = consumer_by_fields[1]

function OAuth2Introspection:new()
  OAuth2Introspection.super.new(self, "oauth2-introspection")
end

local function consumers_username_key(username)
  return fmt("oauth2_introspection_consumer_username:%s", username)
end

local function consumers_id_key(username)
  return fmt("oauth2_introspection_consumer_id:%s", username)
end

local function retrieve_parameters()
  ngx.req.read_body()
  -- OAuth2 parameters could be in both the querystring or body
  local body_parameters, err
  local content_type = req_get_headers()[CONTENT_TYPE]
  if content_type and string_find(content_type:lower(), "multipart/form-data", nil, true) then
    body_parameters = Multipart(ngx.req.get_body_data(), content_type):get_all()
  elseif content_type and string_find(content_type:lower(), "application/json", nil, true) then
    body_parameters, err = cjson.decode(ngx.req.get_body_data())
    if err then body_parameters = {} end
  else
    body_parameters = ngx.req.get_post_args()
  end

  return utils.table_merge(ngx.req.get_uri_args(), body_parameters)
end

local function parse_access_token(conf)
  local found_in = {}
  local result = retrieve_parameters()["access_token"]
  if not result then
    local authorization = ngx.req.get_headers()["authorization"]
    if authorization then
      local parts = {}
      for v in authorization:gmatch("%S+") do -- Split by space
        table_insert(parts, v)
      end
      if #parts == 2 and (parts[1]:lower() == "token" or parts[1]:lower() == "bearer") then
        result = parts[2]
        found_in.authorization_header = true
      end
    end
  end

  if conf.hide_credentials then
    if found_in.authorization_header then
      ngx.req.clear_header("authorization")
    else
      -- Remove from querystring
      local parameters = ngx.req.get_uri_args()
      parameters[ACCESS_TOKEN] = nil
      ngx.req.set_uri_args(parameters)

      if ngx.req.get_method() ~= "GET" then -- Remove from body
        ngx.req.read_body()
        parameters = ngx.req.get_post_args()
        parameters[ACCESS_TOKEN] = nil
        local encoded_args = ngx.encode_args(parameters)
        ngx.req.set_header(CONTENT_LENGTH, #encoded_args)
        ngx.req.set_body_data(encoded_args)
      end
    end
  end

  return result
end

local function make_introspection_request(conf, access_token)
  local parsed_url = url.parse(conf.introspection_url)

  local host = parsed_url.host
  local is_https = parsed_url.scheme == "https"
  local port = parsed_url.port or (is_https and 443 or 80)
  local path = parsed_url.path

  -- Trigger request
  local client = http.new()

  client:set_timeout(conf.timeout)

  local ok, err = client:connect(host, port)
  if not ok then
    return false, err
  end

  if is_https then
    ok, err = client:ssl_handshake()
    if not ok then
      return false, err
    end
  end

  local res, err = client:request {
    method = "POST",
    path = path,
    body = ngx.encode_args({
      token = access_token,
      token_type_hint = conf.token_type_hint
    }),
    headers = {
      ["Content-Type"] = "application/x-www-form-urlencoded",
      Accept = "application/json",
      Authorization = conf.authorization_value
    }
  }
  if not res then
    return false, err
  end

  local status = res.status
  local body = res:read_body()

  ok, err = client:set_keepalive(conf.keepalive)
  if not ok then
    ngx_log(WARN, "failed moving conn to keepalive pool: ", err)
  end

  return status == 200, body
end

local function load_credential(conf, access_token)
  local ok, res = make_introspection_request(conf, access_token)
  if not ok then
    return { err = { status = 500, message = res } }
  end

  local credential = cjson.decode(res)
  if not credential.active then
    return { err = {status=401,
                 message = {error = "invalid_token",
                 error_description = "The access token is invalid or has expired"},
                 headers = {["WWW-Authenticate"] = 'Bearer realm="service" error="invalid_token" error_description="The access token is invalid or has expired"'}}}
  end

  credential.id = access_token -- Setting an unique ID to the credential that can be
                               -- used by other plugins

  return { res = credential }
end

local function load_consumer(username)
  return kong.db.consumers:select_by_username(username)
end

local function load_consumer_mem(consumer_id, anonymous)
  local result, err = kong.db.consumers:select { id = consumer_id }
  if not result then
    if anonymous and not err then
      err = 'anonymous consumer "' .. consumer_id .. '" not found'
    end
    return nil, err
  end
  return result
end

local function set_anonymous_consumer(consumer)
  ngx_set_header(constants.HEADERS.CONSUMER_ID, consumer.id)
  ngx_set_header(constants.HEADERS.CONSUMER_CUSTOM_ID, consumer.custom_id)
  ngx_set_header(constants.HEADERS.CONSUMER_USERNAME, consumer.username)
  ngx.ctx.authenticated_consumer = consumer
  ngx_set_header(constants.HEADERS.ANONYMOUS, true)
end

local function do_authentication(conf)

  local access_token = parse_access_token(conf);
  if not access_token or access_token == "" then
    return false, {
      status = 401,
      message = {
        error = "invalid_request",
        error_description = "The access token is missing"
      },
      headers = {["WWW-Authenticate"] = 'Bearer realm="service"'},
    }
  end

  local cache = kong.cache
  local cache_key = fmt("oauth2_introspection:%s", access_token)
  local credential, err = kong.cache:get(cache_key,
                                              { ttl = conf.ttl },
                                              load_credential, conf,
                                              access_token)
  if err then
    ngx_log(ERR, err)
  end
  local credential_err = credential.err
  if credential_err then
    return false, {
      status = credential_err.status,
      message = credential_err.message,
      headers = credential_err.headers,
    }
  end

  -- Associate username with Kong consumer
  local consumer_by = conf.consumer_by or CONSUMER_BY_DEFAULT

  local credential_obj = credential.res
  if credential_obj and credential_obj[consumer_by] then
    cache_key = consumers_username_key(credential_obj[consumer_by])
    local consumer, err = cache:get(cache_key, nil, load_consumer,
                                           credential_obj[consumer_by])

    if err then
      return false, {status = 500, message = err}
    end
    if consumer then
      cache_key = consumers_id_key(consumer.id)
      local _, err = cache:get(cache_key, nil,
                                function(consumer)
                                  return consumer.username
                                end, consumer)
      if err then
        return false, {status = 500, message = err}
      end

      ngx_set_header(constants.HEADERS.CONSUMER_ID, consumer.id)
      ngx_set_header(constants.HEADERS.CONSUMER_CUSTOM_ID, consumer.custom_id)
      ngx_set_header(constants.HEADERS.CONSUMER_USERNAME, consumer.username)
      ngx.ctx.authenticated_consumer = consumer
      credential_obj.consumer_id = consumer.id
    end
  end

  ngx.ctx.authenticated_credential = credential_obj

  -- Set upstream headers
  ngx_set_header("x-credential-scope", credential_obj.scope)
  ngx_set_header("x-credential-client-id", credential_obj.client_id)
  ngx_set_header("x-credential-username", credential_obj.username)
  ngx_set_header("x-credential-token-type", credential_obj.token_type)
  ngx_set_header("x-credential-exp", credential_obj.exp)
  ngx_set_header("x-credential-iat", credential_obj.iat)
  ngx_set_header("x-credential-nbf", credential_obj.nbf)
  ngx_set_header("x-credential-sub", credential_obj.sub)
  ngx_set_header("x-credential-aud", credential_obj.aud)
  ngx_set_header("x-credential-iss", credential_obj.iss)
  ngx_set_header("x-credential-jti", credential_obj.jti)
  ngx_set_header(constants.HEADERS.ANONYMOUS, nil) -- in case of auth plugins concatenation
  return true
end

function OAuth2Introspection:access(conf)
  OAuth2Introspection.super.access(self)

  if not conf.run_on_preflight and get_method() == "OPTIONS" then
    return
  end

  if ngx.ctx.authenticated_credential and conf.anonymous ~= "" then
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
        load_consumer_mem,
        conf.anonymous, true)
      if err then
        return kong.response.exit(500, err)
      end
      set_anonymous_consumer(consumer)

    else
      return kong.response.exit(401, err.message, err.headers)
    end
  end
end

function OAuth2Introspection:init_worker()
  local worker_events = kong.worker_events
  local cache = kong.cache

  worker_events.register(function(data)
    local consumer_id_key = consumers_id_key(data.old_entity and
                              data.old_entity.id or data.entity.id)
    local username, err = cache:get(consumer_id_key, nil, function() end)
    if err then
      ngx_log(ERR, err)
      return
    end

    cache:invalidate(consumers_username_key(username))
    cache:invalidate(consumer_id_key)
  end, "crud", "consumers")
end

OAuth2Introspection.PRIORITY = 1700
OAuth2Introspection.VERSION = "0.3.2"
OAuth2Introspection.consumers_username_key = consumers_username_key
OAuth2Introspection.consumers_id_key = consumers_id_key
OAuth2Introspection.consumer_by_fields = consumer_by_fields
OAuth2Introspection.CONSUMER_BY_DEFAULT = CONSUMER_BY_DEFAULT

return OAuth2Introspection
