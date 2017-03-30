-- Copyright (C) Mashape, Inc.

local BasePlugin = require "kong.plugins.base_plugin"
local cache = require "kong.tools.database_cache"
local responses = require "kong.tools.responses"
local constants = require "kong.constants"
local singletons = require "kong.singletons"

local utils = require "kong.tools.utils"
local Multipart = require "multipart"
local cjson = require "cjson.safe"
local http = require "resty.http"
local url = require "socket.url"

local OAuth2Introspection = BasePlugin:extend()

local CONTENT_TYPE = "content-type"
local CONTENT_LENGTH = "content-length"
local ACCESS_TOKEN = "access_token"

local req_get_headers = ngx.req.get_headers
local ngx_set_header = ngx.req.set_header
local string_find = string.find
local table_insert = table.insert
local fmt = string.format

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
  client:connect(host, port)
  client:set_timeout(conf.timeout)
  if is_https then
    local ok, err = client:ssl_handshake()
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

  local ok, err = client:set_keepalive(conf.keepalive)
  if not ok then
    return false, err
  end

  return status == 200, body
end

local function load_credential(conf, access_token)
  local ok, res = make_introspection_request(conf, access_token)
  if not ok then
    return nil, {status=500, message=res}
  end

  local credential = cjson.decode(res)
  if not credential.active then
    return nil, {status=401,
                 message={["error"] = "invalid_token",
                 error_description = "The access token is invalid or has expired"},
                 headers = {["WWW-Authenticate"] = 'Bearer realm="service" error="invalid_token" error_description="The access token is invalid or has expired"'}}
  end

  return credential
end

local function load_consumer(username)
  local result, err = singletons.dao.consumers:find_all { username = username }
  if not result then
    return nil, err
  elseif #result == 1 then
    return result[1]
  end
end

function OAuth2Introspection:access(conf)
  OAuth2Introspection.super.access(self)
  
  local access_token = parse_access_token(conf);
  if not access_token or access_token == "" then
    return responses.send(401,
      {["error"] = "invalid_request",
      error_description = "The access token is missing"},
      {["WWW-Authenticate"] = 'Bearer realm="service"'})
  end

  local credential, err = cache.get_or_set(fmt("oauth2_introspection:%s", access_token), conf.ttl, 
    load_credential, conf, access_token)
  if err then
    return responses.send(err.status, err.message, err.headers)
  end

  -- Associate username with Kong consumer
  if credential.username then
    local consumer, err = cache.get_or_set(consumers_username_key(credential.username),
                       nil, load_consumer, credential.username)
    if err then
       responses.send_HTTP_INTERNAL_SERVER_ERROR(err)
    end
    if consumer then
      local _, err = cache.get_or_set(consumers_id_key(consumer.id),
                        nil, function(consumer) return consumer.username end, consumer)
      if err then
        responses.send_HTTP_INTERNAL_SERVER_ERROR(err)
      end
      
      ngx_set_header(constants.HEADERS.CONSUMER_ID, consumer.id)
      ngx_set_header(constants.HEADERS.CONSUMER_CUSTOM_ID, consumer.custom_id)
      ngx_set_header(constants.HEADERS.CONSUMER_USERNAME, consumer.username)
      ngx.ctx.authenticated_consumer = consumer
    end
  end

  ngx.ctx.authenticated_credential = credential

  -- Set upstream headers
  ngx_set_header("x-scope", credential.scope)
  ngx_set_header("x-client-id", credential.client_id)
  ngx_set_header("x-username", credential.username)
  ngx_set_header("x-token-type", credential.token_type)
  ngx_set_header("x-exp", credential.exp)
  ngx_set_header("x-iat", credential.iat)
  ngx_set_header("x-nbf", credential.nbf)
  ngx_set_header("x-sub", credential.sub)
  ngx_set_header("x-aud", credential.aud)
  ngx_set_header("x-iss", credential.iss)
  ngx_set_header("x-jti", credential.jti)
  ngx_set_header(constants.HEADERS.ANONYMOUS, nil) -- in case of auth plugins concatenation
end

OAuth2Introspection.PRIORITY = 1000
OAuth2Introspection.consumers_username_key = consumers_username_key
OAuth2Introspection.consumers_id_key = consumers_id_key

return OAuth2Introspection
